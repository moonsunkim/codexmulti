import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { once } from 'node:events';
import { stat } from 'node:fs/promises';
import { requestRefresh } from '../src/accounts.mjs';
import { startHttpServer, startTestProxy, syntheticAuth, request, jwt } from './helpers.mjs';

function upgrade(origin, headers = {}) {
  const url = new URL(origin);
  return new Promise((resolve, reject) => {
    const socket = net.connect(Number(url.port), '127.0.0.1');
    let output = '';
    socket.once('error', reject);
    socket.on('data', (chunk) => {
      output += chunk.toString('latin1');
      if (output.includes('\r\n\r\n')) resolve({ socket, output });
    });
    socket.once('connect', () => socket.write([
      'GET /backend-api/codex/responses HTTP/1.1', `Host: ${url.host}`,
      'Connection: Upgrade', 'Upgrade: websocket', 'Sec-WebSocket-Version: 13',
      'Sec-WebSocket-Key: c3ludGhldGljLWtleQ==',
      ...Object.entries(headers).map(([k,v]) => `${k}: ${v}`), '', ''
    ].join('\r\n')));
  });
}

test('foreign Origin and Host cannot change local control state', async (t) => {
  const upstream = await startHttpServer(t, (_req,res) => res.end('synthetic'));
  const p = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const result = await request(p.origin, '/_proxy/accounts/a/pause', {
    method: 'POST', headers: { 'content-type': 'application/json', Origin: 'http://foreign.example', Host: 'foreign.example' }, body: '{}'
  });
  assert.equal(result.statusCode, 403);
  assert.equal(p.proxy.failover.stateOf('a'), 'READY');
});

test('control API requires the owner capability even with a valid loopback Host', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.end());
  const p = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const tokenStat = await stat(p.proxy.config.control_token_file);
  assert.equal(tokenStat.mode & 0o777, 0o600);
  assert.equal(tokenStat.uid, process.getuid());
  for (const headers of [{}, {authorization: 'Bearer wrong'}]) {
    const result = await request(p.origin, '/_proxy/accounts/a/pause', {
      controlAuth: false, method: 'POST', headers: {'content-type': 'application/json', ...headers}, body: '{}',
    });
    assert.equal(result.statusCode, 401);
    assert.equal(p.proxy.failover.stateOf('a'), 'READY');
  }
  for (const headers of [{Origin: 'null'}, {'Sec-Fetch-Site': 'same-origin'}, {Host: 'foreign.example'}]) {
    const result = await request(p.origin, '/_proxy/status', { headers });
    assert.equal(result.statusCode, 403);
  }
  assert.equal((await request(p.origin, '/_proxy/accounts/a/pause', {
    method: 'POST', headers: {'content-type':'application/json'}, body: '{}',
  })).statusCode, 202);
});

for (const transport of ['HTTP', 'WebSocket']) {
  test(`${transport} response-header deadline releases a silent upstream without replay`, async (t) => {
    let calls = 0;
    const upstream = await startHttpServer(t, (_req, _res) => { calls += 1; });
    const p = await startTestProxy(t, {
      upstreamOrigin: upstream.origin, accountNames: ['a', 'b'], config: {upstream_headers_timeout_ms: 50},
    });
    if (transport === 'HTTP') {
      const result = await request(p.origin, '/backend-api/codex/responses', {method:'POST', body:'{}'});
      assert.equal(result.statusCode, 502);
    } else {
      const result = await upgrade(p.origin);
      result.socket.destroy();
      assert.match(result.output, /^HTTP\/1.1 502/);
    }
    assert.equal(calls, 1);
    assert.equal((await p.proxy.statusPayload()).in_flight, 0);
    assert.equal((await request(p.origin, '/_proxy/reload-config', {
      method:'POST', headers:{'content-type':'application/json'}, body:'{}',
    })).statusCode, 200);
  });
}

test('OAuth 429 and 503 are temporary failures while 400 is an authentication rejection', async (t) => {
  let statusCode = 429;
  const oauth = await startHttpServer(t, (_req, res) => res.writeHead(statusCode).end('{}'));
  for (const status of [429, 503, 400]) {
    statusCode = status;
    await assert.rejects(requestRefresh(oauth.origin, 'synthetic-refresh'), {
      message: status === 400 ? 'refresh_rejected' : 'refresh_unavailable',
    });
  }
});

test('foreign-origin websocket is rejected before pooled credentials reach upstream', async (t) => {
  const upstream = await startHttpServer(t, (_req,res) => res.end());
  let hasPooledIdentity = false;
  let upstreamSocket;
  upstream.server.on('upgrade', (req, socket) => {
    socket.on('end', () => socket.destroy());
    socket.on('error', () => socket.destroy());
    upstreamSocket = socket;
    hasPooledIdentity = req.headers['chatgpt-account-id'] === 'synthetic-account-a' && req.headers.authorization?.startsWith('Bearer ');
    t.after(() => socket.destroy());
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
  });
  const p = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const result = await upgrade(p.origin, { Origin: 'http://foreign.example' });
  assert.match(result.output, /^HTTP\/1.1 403/);
  assert.equal(hasPooledIdentity, false);
  result.socket.destroy();
  upstreamSocket?.destroy();
});

test('websocket reaches the third ready account after two definitive usage limits', async (t) => {
  const upstream = await startHttpServer(t, (_req,res) => res.end());
  const calls = [];
  upstream.server.on('upgrade', (req, socket) => {
    socket.on('end', () => socket.destroy());
    socket.on('error', () => socket.destroy());
    const name = req.headers['chatgpt-account-id'].replace('synthetic-account-', '');
    calls.push(name);
    if (name === 'c') {
      t.after(() => socket.destroy());
      socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
    } else {
      const body = JSON.stringify({error:{type:'usage_limit_reached',resets_at:Math.floor(Date.now()/1000)+3600}});
      socket.end(`HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\nContent-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
    }
  });
  const p = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a','b','c'] });
  const result = await upgrade(p.origin);
  result.socket.destroy();
  assert.deepEqual(calls, ['a','b','c']);
  assert.match(result.output, /^HTTP\/1.1 101/);
  assert.equal(p.proxy.failover.stateOf('c'), 'READY');
});

test('cancelling before response headers releases the lease and allows reload', async (t) => {
  let upstreamRequest;
  let seen;
  const started = new Promise(resolve => { seen = resolve; });
  const upstream = await startHttpServer(t, (req, _res) => { upstreamRequest = req; seen(); });
  const p = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const req = http.request(`${p.origin}/backend-api/codex/responses`, {method:'POST'});
  req.on('error', () => {});
  req.end('{}');
  await started;
  const closed = new Promise(resolve => req.once('close', resolve));
  req.destroy();
  await closed;
  await new Promise(resolve => setTimeout(resolve, 200));
  const status = await p.proxy.statusPayload();
  assert.equal(status.accounts[0].in_flight, 0);
  const reload = await request(p.origin, '/_proxy/reload-config', {method:'POST',headers:{'content-type':'application/json'},body:'{}'});
  assert.equal(reload.statusCode, 200);
  upstreamRequest.socket.destroy();
});

test('temporary renewal outage keeps a valid token usable and clears its warning after retry', async (t) => {
  const upstream = await startHttpServer(t, (_req,res) => res.end('synthetic success'));
  let now = Date.now();
  let outage = true;
  const p = await startTestProxy(t, {
    upstreamOrigin: upstream.origin, accountNames:['a'], now,
    authByName:{a:syntheticAuth('a',Math.floor(now/1000)+86400)},
    options:{now: () => now, refreshRequest:async () => {
      if (outage) throw new Error('synthetic_network_outage');
      return {access_token: jwt({exp: Math.floor(now/1000)+10*86400}), refresh_token:'synthetic-rotated'};
    }}
  });
  await p.proxy.runTokenRenewalCycle();
  assert.equal(p.proxy.failover.stateOf('a'), 'READY');
  assert.ok(p.proxy.registry.tokenExpiresAt('a') > now/1000);
  assert.equal((await p.proxy.statusPayload()).accounts[0].token_refresh.last_error, 'network');
  const result = await request(p.origin, '/backend-api/codex/responses', {method:'POST',body:'{}'});
  assert.equal(result.statusCode,200);
  outage = false;
  now += 3600_000;
  await p.proxy.runTokenRenewalCycle();
  const recovered = (await p.proxy.statusPayload()).accounts[0];
  assert.equal(recovered.state, 'READY');
  assert.equal(recovered.token_refresh.last_error, null);
  assert.equal(recovered.token_refresh.last_ok_at, new Date(now).toISOString());
});
