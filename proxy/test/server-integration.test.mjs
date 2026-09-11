import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { chmod, readFile } from 'node:fs/promises';
import { gzipSync, zstdCompressSync } from 'node:zlib';
import { REFRESH_CLIENT_ID, atomicWriteJson } from '../src/accounts.mjs';
import { AccountState, FailoverManager } from '../src/failover.mjs';
import {
  jwt,
  makeTempDir,
  request,
  sseOk,
  startHttpServer,
  startTestProxy,
  syntheticAuth,
} from './helpers.mjs';

async function readIncoming(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

function tokenPayload(req) {
  const token = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
  try {
    return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
  } catch {
    return {};
  }
}

test('pre-stream usage limit is persisted and byte-identical request is replayed to the next READY account', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const bodies = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    const body = await readIncoming(req);
    bodies.push({ name: tokenPayload(req).token_name, body, headers: req.headers });
    if (tokenPayload(req).token_name === 'a') {
      const error = Buffer.from(JSON.stringify({
        error: { type: 'usage_limit_reached', resets_at: Math.floor(now / 1000) + 120 },
      }));
      res.writeHead(429, { 'content-type': 'application/json', 'content-length': String(error.length) });
      res.end(error);
      return;
    }
    const stream = sseOk();
    res.writeHead(200, { 'content-type': 'text/event-stream', 'x-request-id': 'synthetic-upstream' });
    res.end(stream);
  });
  const { origin, root } = await startTestProxy(t, { upstreamOrigin: upstream.origin, now });
  const body = Buffer.from([0x28, 0xb5, 0x2f, 0xfd, 1, 2, 3, 4]);
  const response = await request(origin, '/backend-api/codex/responses?fixture=1', {
    method: 'POST',
    body,
    headers: {
      'content-type': 'application/json',
      'content-encoding': 'zstd',
      authorization: 'Bearer should-be-replaced',
      'chatgpt-account-id': 'should-be-replaced',
      'session-id': 'synthetic-session',
      'openai-beta': 'synthetic-beta',
      'x-codex-fixture': 'preserve-me',
    },
  });
  assert.equal(response.statusCode, 200);
  assert.match(response.body.toString(), /"text":"ok"/);
  assert.deepEqual(bodies.map(({ name }) => name), ['a', 'b']);
  assert.deepEqual(bodies[0].body, body);
  assert.deepEqual(bodies[1].body, body);
  assert.equal(bodies[1].headers['content-encoding'], 'zstd');
  assert.equal(bodies[1].headers['session-id'], 'synthetic-session');
  assert.equal(bodies[1].headers['openai-beta'], 'synthetic-beta');
  assert.equal(bodies[1].headers['x-codex-fixture'], 'preserve-me');
  const status = JSON.parse((await request(origin, '/_proxy/status')).body);
  assert.equal(status.active, 'b');
  assert.equal(status.accounts.find((account) => account.name === 'a').state, 'COOLDOWN');
  assert.equal(status.accounts.find((account) => account.name === 'a').cooldown_until,
    new Date(now + 180_000).toISOString());
  assert.doesNotMatch(JSON.stringify(status), /synthetic-refresh|synthetic-account/);
  const persistedState = await readFile(path.join(root, 'state/state.json'), 'utf8');
  assert.doesNotMatch(persistedState, /synthetic-refresh|synthetic-account|eyJ/);
});

test('all-cooldown selects the earliest account exactly once and returns a byte-identical 429', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const calls = [];
  const raw429 = Buffer.from(JSON.stringify({ error: { type: 'usage_limit_reached', resets_at: Math.floor(now / 1000) + 500 } }));
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    calls.push(tokenPayload(req).token_name);
    res.writeHead(429, { 'content-type': 'application/json', 'content-length': String(raw429.length), 'x-fixture': 'original' });
    res.end(raw429);
  });
  const { proxy, origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, now });
  await proxy.failover.markCooldown('a', now + 10_000);
  await proxy.failover.markCooldown('b', now + 20_000);
  await proxy.failover.markCooldown('c', now + 30_000);
  const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(response.statusCode, 429);
  assert.deepEqual(response.body, raw429);
  assert.equal(response.headers['x-fixture'], 'original');
  assert.deepEqual(calls, ['a']);
});

test('successful all-cooldown probe clears only the earliest account', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const calls = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    calls.push(tokenPayload(req).token_name);
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end(sseOk());
  });
  const { proxy, origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, now });
  await proxy.failover.markCooldown('a', now + 10_000);
  await proxy.failover.markCooldown('b', now + 20_000);
  await proxy.failover.markCooldown('c', now + 30_000);
  assert.equal((await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' })).statusCode, 200);
  assert.deepEqual(calls, ['a']);
  assert.equal(proxy.failover.stateOf('a'), AccountState.READY);
  assert.equal(proxy.failover.stateOf('b'), AccountState.COOLDOWN);
});

for (const probeRoute of ['/backend-api/wham/usage', '/backend-api/ps/plugins/synthetic']) {
  test(`all-cooldown 200 probe on ${probeRoute} relays without clearing the cooldown`, async (t) => {
    const now = Date.UTC(2030, 0, 1);
    const calls = [];
    const payload = Buffer.from(JSON.stringify({ fixture: 'non-model-route' }));
    const upstream = await startHttpServer(t, async (req, res) => {
      await readIncoming(req);
      calls.push(req.url);
      res.writeHead(200, {
        'content-type': 'application/json', 'content-length': String(payload.length),
      });
      res.end(payload);
    });
    const { proxy, origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, now });
    await proxy.failover.markCooldown('a', now + 10_000);
    await proxy.failover.markCooldown('b', now + 20_000);
    await proxy.failover.markCooldown('c', now + 30_000);
    const response = await request(origin, probeRoute);
    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.body, payload);
    assert.deepEqual(calls, [probeRoute]);
    assert.equal(proxy.failover.stateOf('a'), AccountState.COOLDOWN);
    assert.equal(proxy.failover.snapshot().accounts.a.cooldown_until,
      new Date(now + 10_000).toISOString());
    assert.equal(proxy.failover.snapshot().accounts.a.reason, 'usage_limit_reached');
  });
}

for (const [label, probeRoute, method] of [
  ['Responses', '/backend-api/codex/responses', 'POST'],
  ['non-model', '/backend-api/wham/usage', 'GET'],
]) {
  test(`all-cooldown usage-limit probe on the ${label} route updates the cooldown`, async (t) => {
    const now = Date.UTC(2030, 0, 1);
    const raw429 = Buffer.from(JSON.stringify({
      error: { type: 'usage_limit_reached', resets_at: Math.floor(now / 1000) + 900 },
    }));
    const calls = [];
    const upstream = await startHttpServer(t, async (req, res) => {
      await readIncoming(req);
      calls.push(tokenPayload(req).token_name);
      res.writeHead(429, {
        'content-type': 'application/json', 'content-length': String(raw429.length),
      });
      res.end(raw429);
    });
    const { proxy, origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, now });
    await proxy.failover.markCooldown('a', now + 10_000);
    await proxy.failover.markCooldown('b', now + 20_000);
    await proxy.failover.markCooldown('c', now + 30_000);
    const response = await request(origin, probeRoute, method === 'POST'
      ? { method, body: '{}' } : {});
    assert.equal(response.statusCode, 429);
    assert.deepEqual(response.body, raw429);
    assert.deepEqual(calls, ['a']);
    assert.equal(proxy.failover.stateOf('a'), AccountState.COOLDOWN);
    assert.equal(proxy.failover.snapshot().accounts.a.cooldown_until,
      new Date(now + 960_000).toISOString());
  });
}

for (const [encoding, compress] of [['gzip', gzipSync], ['zstd', zstdCompressSync]]) {
  test(`all-cooldown ${encoding} 429 preserves compressed body and headers byte-for-byte`, async (t) => {
    const now = Date.UTC(2030, 0, 1);
    const raw = compress(Buffer.from(JSON.stringify({
      error: { type: 'usage_limit_reached', resets_at: Math.floor(now / 1000) + 300 },
    })));
    let calls = 0;
    const upstream = await startHttpServer(t, async (req, res) => {
      await readIncoming(req);
      calls += 1;
      res.writeHead(429, {
        'content-type': 'application/json', 'content-encoding': encoding,
        'content-length': String(raw.length), 'x-original': encoding,
      });
      res.end(raw);
    });
    const { proxy, origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, now, accountNames: ['a'] });
    await proxy.failover.markCooldown('a', now + 10_000);
    const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
    assert.equal(response.statusCode, 429);
    assert.equal(response.headers['content-encoding'], encoding);
    assert.equal(response.headers['x-original'], encoding);
    assert.deepEqual(response.body, raw);
    assert.equal(calls, 1);
  });
}

test('fake-upstream reset body/header/default sources all include the configured safety margin', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const variants = [
    {
      body: { error: { type: 'usage_limit_reached', resets_at: nowSeconds + 100 } },
      headers: {}, expected: now + 160_000,
    },
    {
      body: { error: { type: 'usage_limit_reached' } },
      headers: {
        'x-codex-active-limit': 'team',
        'x-codex-rate-limit-reached-type': 'secondary',
        'x-team-secondary-reset-at': String(nowSeconds + 200),
      },
      expected: now + 260_000,
    },
    {
      body: { error: { type: 'usage_limit_reached' } },
      headers: {}, expected: now + 1_860_000,
    },
  ];
  for (const [index, variant] of variants.entries()) {
    await t.test(`reset variant ${index + 1}`, async (subtest) => {
      const upstream = await startHttpServer(subtest, async (req, res) => {
        await readIncoming(req);
        const token = tokenPayload(req).token_name;
        if (token === 'a') {
          const raw = Buffer.from(JSON.stringify(variant.body));
          res.writeHead(429, { 'content-type': 'application/json', 'content-length': String(raw.length), ...variant.headers });
          res.end(raw);
        } else {
          res.writeHead(200, { 'content-type': 'text/event-stream' }).end(sseOk());
        }
      });
      const { proxy, origin } = await startTestProxy(subtest, { upstreamOrigin: upstream.origin, now, accountNames: ['a', 'b'] });
      assert.equal((await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' })).statusCode, 200);
      assert.equal(proxy.failover.snapshot().accounts.a.cooldown_until, new Date(variant.expected).toISOString());
    });
  }
});

test('401 disk reload retries the same account once without switching accounts', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const oldAuth = syntheticAuth('a', nowSeconds + 3600);
  const nextToken = jwt({ exp: nowSeconds + 3600, token_name: 'a', generation: 'disk-reload' });
  let authFile;
  const seen = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    const payload = tokenPayload(req);
    seen.push(payload);
    if (!payload.generation) {
      const disk = JSON.parse(await readFile(authFile, 'utf8'));
      disk.tokens.access_token = nextToken;
      await atomicWriteJson(authFile, disk);
      res.writeHead(401).end('first');
      return;
    }
    res.writeHead(200, { 'content-type': 'text/event-stream' }).end(sseOk());
  });
  const started = await startTestProxy(t, {
    temp: root,
    upstreamOrigin: upstream.origin,
    now,
    accountNames: ['a', 'b'],
    authByName: { a: oldAuth },
    options: { refreshRequest: async () => { throw new Error('refresh must not run'); } },
  });
  authFile = started.accounts.find((account) => account.name === 'a').auth_file;
  const response = await request(started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(seen.map((payload) => payload.token_name), ['a', 'a']);
  assert.equal(seen[1].generation, 'disk-reload');
});

test('401 refresh rotates the token and retries the same account once', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const refreshedToken = jwt({ exp: nowSeconds + 7200, token_name: 'a', generation: 'refreshed' });
  let refreshes = 0;
  const refreshServer = await startHttpServer(t, async (req, res) => {
    const body = JSON.parse((await readIncoming(req)).toString());
    assert.equal(req.method, 'POST');
    assert.equal(req.url, '/oauth/token');
    assert.equal(req.headers['content-type'], 'application/json');
    assert.equal(body.client_id, REFRESH_CLIENT_ID);
    assert.equal(body.grant_type, 'refresh_token');
    assert.match(body.refresh_token, /^synthetic-refresh-/);
    refreshes += 1;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ access_token: refreshedToken, refresh_token: 'synthetic-refresh-rotated' }));
  });
  const calls = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    const payload = tokenPayload(req);
    calls.push(payload);
    if (!payload.generation) return res.writeHead(401).end('refresh');
    res.writeHead(200, { 'content-type': 'text/event-stream' }).end(sseOk());
  });
  const { origin } = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    now,
    accountNames: ['a', 'b'],
    options: { refreshUrl: `${refreshServer.origin}/oauth/token` },
  });
  const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(response.statusCode, 200);
  assert.equal(refreshes, 1);
  assert.deepEqual(calls.map((payload) => payload.token_name), ['a', 'a']);
  assert.equal(calls[1].generation, 'refreshed');
});

test('forced refresh control reports only result and new access expiry', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    now,
    accountNames: ['a'],
    options: {
      refreshRequest: async () => ({
        access_token: jwt({ exp: nowSeconds + 10 * 86_400, token_name: 'forced-control' }),
        refresh_token: 'synthetic-refresh-forced-control',
      }),
    },
  });
  const response = await request(started.origin, '/_proxy/accounts/a/refresh', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{}',
  });
  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.body);
  assert.deepEqual(Object.keys(body).sort(), ['access_expires_at', 'name', 'result']);
  assert.equal(body.result, 'ok');
  assert.equal(body.access_expires_at, new Date((nowSeconds + 10 * 86_400) * 1000).toISOString());
  assert.doesNotMatch(response.body.toString(), /synthetic-refresh|account_id|access_token|id_token|eyJ/);
});

test('failed forced refresh marks the account INVALID and returns a safe result', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { refreshRequest: async () => { throw new Error('synthetic_refresh_failure'); } },
  });
  const response = await request(started.origin, '/_proxy/accounts/a/refresh', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{}',
  });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), {
    name: 'a', result: 'failed', access_expires_at: null,
  });
  const status = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.equal(status.accounts[0].state, 'INVALID');
});

test('startup warns on duplicate account identity without rejecting either file', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const sharedIdentity = 'synthetic-shared-startup-identity';
  const events = [];
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b'],
    authByName: {
      a: syntheticAuth('a', 4_102_444_800, { tokens: { account_id: sharedIdentity } }),
      b: syntheticAuth('b', 4_102_444_800, { tokens: { account_id: sharedIdentity } }),
    },
    options: { logger: (event) => events.push(event) },
  });
  assert.equal((await started.proxy.statusPayload()).accounts.length, 2);
  assert.deepEqual(events, [{
    timestamp: events[0].timestamp,
    level: 'warn',
    event: 'duplicate_account_identity',
    account_name: 'b',
  }]);
  assert.doesNotMatch(JSON.stringify(events), /synthetic-shared-startup-identity/);
});

test('second 401 is returned terminally and never switches to a different account', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const calls = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    calls.push(tokenPayload(req).token_name);
    res.writeHead(401, { 'x-fixture': 'second-401' }).end('unauthorized');
  });
  const { origin } = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    now,
    accountNames: ['a', 'b'],
    options: {
      refreshRequest: async () => ({ access_token: jwt({ exp: nowSeconds + 7200, token_name: 'a', generation: 'refreshed' }) }),
    },
  });
  const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(response.statusCode, 401);
  assert.equal(response.body.toString(), 'unauthorized');
  assert.equal(response.headers['x-fixture'], 'second-401');
  assert.deepEqual(calls, ['a', 'a']);
});

test('concurrent expired-token requests perform one refresh and preserve auth/state files', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const expired = syntheticAuth('a', nowSeconds - 1);
  let refreshes = 0;
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    assert.equal(tokenPayload(req).generation, 'shared');
    res.writeHead(200, { 'content-type': 'text/event-stream' }).end(sseOk());
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    now,
    accountNames: ['a'],
    authByName: { a: expired },
    options: {
      refreshRequest: async () => {
        refreshes += 1;
        await new Promise((resolve) => setTimeout(resolve, 30));
        return { access_token: jwt({ exp: nowSeconds + 7200, token_name: 'a', generation: 'shared' }) };
      },
    },
  });
  const results = await Promise.all(Array.from({ length: 6 }, () => request(
    started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' },
  )));
  assert.equal(refreshes, 1);
  assert.ok(results.every((response) => response.statusCode === 200));
  assert.doesNotThrow(() => JSON.parse(results[0].body.toString().split('data: ')[1].split('\n')[0]));
  const auth = JSON.parse(await readFile(started.accounts[0].auth_file, 'utf8'));
  const state = JSON.parse(await readFile(path.join(started.root, 'state/state.json'), 'utf8'));
  assert.equal(auth.fixture_marker.preserve, true);
  assert.equal(state.version, 1);
});

test('request body accepts exactly 64 MiB and rejects declared 64 MiB + 1 before upstream', { timeout: 30_000 }, async (t) => {
  let calls = 0;
  let receivedBytes = 0;
  let receivedHash;
  const upstream = await startHttpServer(t, async (req, res) => {
    calls += 1;
    const hash = createHash('sha256');
    for await (const chunk of req) {
      receivedBytes += chunk.length;
      hash.update(chunk);
    }
    receivedHash = hash.digest('hex');
    res.writeHead(204).end();
  });
  const { origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const exact = Buffer.alloc(64 * 1024 * 1024, 0x5a);
  const expectedHash = createHash('sha256').update(exact).digest('hex');
  assert.equal((await request(origin, '/backend-api/codex/upload', { method: 'POST', body: exact })).statusCode, 204);
  assert.equal(receivedBytes, exact.length);
  assert.equal(receivedHash, expectedHash);
  const oversized = await new Promise((resolve, reject) => {
    const req = http.request(`${origin}/backend-api/codex/upload`, {
      method: 'POST', headers: { 'content-length': String(exact.length + 1) },
    }, async (res) => {
      const chunks = [];
      for await (const chunk of res) chunks.push(chunk);
      resolve({ statusCode: res.statusCode, body: Buffer.concat(chunks) });
    });
    req.once('error', reject);
    req.end();
  });
  assert.equal(oversized.statusCode, 413);
  assert.equal(calls, 1);
});

test('SSE streaming propagates backpressure and downstream disconnect aborts upstream', { timeout: 15_000 }, async (t) => {
  let sawBackpressure = false;
  let upstreamClosed = false;
  let call = 0;
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    call += 1;
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.once('close', () => { upstreamClosed = true; });
    if (call === 1) {
      const chunk = Buffer.alloc(64 * 1024, 0x61);
      for (let index = 0; index < 128; index += 1) {
        if (!res.write(chunk)) {
          sawBackpressure = true;
          await new Promise((resolve) => res.once('drain', resolve));
        }
      }
      res.end();
      return;
    }
    const timer = setInterval(() => res.write(Buffer.alloc(16 * 1024, 0x62)), 5);
    res.once('close', () => clearInterval(timer));
  });
  const { origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const bytes = await new Promise((resolve, reject) => {
    http.get(`${origin}/backend-api/codex/stream`, (res) => {
      let total = 0;
      res.pause();
      setTimeout(() => {
        res.on('data', (chunk) => { total += chunk.length; });
        res.on('end', () => resolve(total));
        res.resume();
      }, 75);
    }).once('error', reject);
  });
  assert.equal(bytes, 8 * 1024 * 1024);
  assert.equal(sawBackpressure, true);
  upstreamClosed = false;
  await new Promise((resolve, reject) => {
    const req = http.get(`${origin}/backend-api/codex/disconnect`, (res) => {
      res.once('data', () => {
        req.destroy();
        resolve();
      });
    });
    req.once('error', (error) => error.code === 'ECONNRESET' ? resolve() : reject(error));
  });
  const deadline = Date.now() + 2_000;
  while (!upstreamClosed && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(upstreamClosed, true);
});

test('usage_not_included, plan mismatch, and 5xx are terminal without account switching', async (t) => {
  const variants = [
    { status: 429, body: JSON.stringify({ error: { type: 'usage_not_included' } }) },
    { status: 403, body: JSON.stringify({ error: { type: 'plan_mismatch' } }) },
    { status: 503, body: 'upstream unavailable' },
  ];
  const calls = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    calls.push(tokenPayload(req).token_name);
    const variant = variants.shift();
    res.writeHead(variant.status, { 'x-terminal': String(variant.status) }).end(variant.body);
  });
  const { origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a', 'b'] });
  for (const expected of [429, 403, 503]) {
    const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
    assert.equal(response.statusCode, expected);
    assert.equal(response.headers['x-terminal'], String(expected));
  }
  assert.deepEqual(calls, ['a', 'a', 'a']);
});

test('a 429 body over the 1 MiB classification cap streams unchanged and does not fail over', async (t) => {
  const raw = Buffer.concat([
    Buffer.from('{"error":{"type":"usage_limit_reached"},"padding":"'),
    Buffer.alloc(1024 * 1024, 0x78),
    Buffer.from('"}'),
  ]);
  const calls = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    calls.push(tokenPayload(req).token_name);
    res.writeHead(429, { 'content-type': 'application/json', 'content-length': String(raw.length) });
    res.end(raw);
  });
  const { origin } = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a', 'b'] });
  const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(response.statusCode, 429);
  assert.deepEqual(response.body, raw);
  assert.deepEqual(calls, ['a']);
});

test('transport failure is terminal and does not attempt another account', async (t) => {
  const unavailable = await startHttpServer(t, (_req, res) => res.end());
  const port = unavailable.port;
  await new Promise((resolve) => unavailable.server.close(resolve));
  const { origin } = await startTestProxy(t, {
    upstreamOrigin: `http://127.0.0.1:${port}`,
    accountNames: ['a', 'b'],
  });
  const response = await request(origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(response.statusCode, 502);
  assert.match(response.body.toString(), /proxy_upstream_transport_error/);
});

test('runtime auth validation failure marks the selected account INVALID', async (t) => {
  let upstreamAttempts = 0;
  const upstream = await startHttpServer(t, (_req, res) => {
    upstreamAttempts += 1;
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end(sseOk());
  });
  const now = Date.UTC(2030, 0, 1);
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    now,
    authByName: { a: syntheticAuth('a', Math.floor(now / 1000) - 1) },
    options: { refreshRequest: async () => assert.fail('refresh must not run after auth validation failure') },
  });
  await chmod(started.accounts[0].auth_file, 0o644);
  const response = await request(started.origin, '/backend-api/codex/responses', {
    method: 'POST', body: '{}', headers: { 'content-type': 'application/json' },
  });
  assert.equal(response.statusCode, 503);
  assert.equal(JSON.parse(response.body).error, 'proxy_account_invalid');
  assert.equal(upstreamAttempts, 0);
  const status = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.equal(status.accounts[0].state, 'INVALID');
});

test('state persistence failure releases the in-flight lease', async (t) => {
  const events = [];
  const upstream = await startHttpServer(t, async (_req, res) => {
    const body = Buffer.from(JSON.stringify({ error: { type: 'usage_limit_reached' } }));
    res.writeHead(429, { 'content-type': 'application/json', 'content-length': String(body.length) });
    res.end(body);
  });
  const failover = new FailoverManager(['a']);
  await failover.initialize();
  failover.markCooldown = async () => {
    const error = new Error(`Bearer synthetic-state-secret-${'x'.repeat(300)}`);
    error.code = 'SYNTHETIC_STATE_FAILURE';
    throw error;
  };
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { failover, logger: (event) => events.push(event) },
  });
  const response = await request(started.origin, '/backend-api/codex/responses', {
    method: 'POST', body: '{}', headers: { 'content-type': 'application/json' },
  });
  assert.equal(response.statusCode, 500);
  assert.equal((await started.proxy.statusPayload()).in_flight, 0);
  const requestError = events.find(({ event }) => event === 'request_error');
  assert.equal(requestError.error_code, 'SYNTHETIC_STATE_FAILURE');
  assert.equal(requestError.upstream_status, 429);
  assert.equal(typeof requestError.duration_ms, 'number');
  assert.ok(requestError.error_message.length <= 200);
  assert.match(requestError.error_message, /<redacted>/);
  assert.doesNotMatch(requestError.error_message, /synthetic-state-secret/);
});

test('control pause returns 202 immediately, blocks new selection, and exposes drain through status', async (t) => {
  let releaseA;
  const held = new Promise((resolve) => { releaseA = resolve; });
  t.after(() => releaseA());
  let aStarted;
  const began = new Promise((resolve) => { aStarted = resolve; });
  const calls = [];
  const upstream = await startHttpServer(t, async (req, res) => {
    await readIncoming(req);
    const name = tokenPayload(req).token_name;
    calls.push(name);
    if (name === 'a') {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write('event: response.created\ndata: {"type":"response.created","response":{"id":"held"}}\n\n');
      aStarted();
      await held;
      res.end(sseOk('held-complete'));
      return;
    }
    res.writeHead(200, { 'content-type': 'text/event-stream' }).end(sseOk('b-response'));
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a', 'b'] });
  const first = request(started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  await began;
  const pauseRequest = request(started.origin, '/_proxy/accounts/a/pause', {
    method: 'POST', body: '{}', headers: { 'content-type': 'application/json' },
  });
  const pause = await Promise.race([
    pauseRequest,
    new Promise((_, reject) => setTimeout(() => reject(new Error('pause_did_not_return_immediately')), 250)),
  ]);
  assert.equal(pause.statusCode, 202);
  assert.deepEqual(JSON.parse(pause.body), { name: 'a', state: 'PAUSED', in_flight: 1 });
  const draining = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.equal(draining.accounts.find((account) => account.name === 'a').in_flight, 1);
  const second = await request(started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(second.statusCode, 200);
  assert.equal(calls.at(-1), 'b');
  releaseA();
  assert.equal((await first).statusCode, 200);
  const paused = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.equal(paused.accounts.find((account) => account.name === 'a').state, 'PAUSED');
  assert.equal(paused.accounts.find((account) => account.name === 'a').in_flight, 0);
  const reloaded = await request(started.origin, '/_proxy/accounts/a/reload', {
    method: 'POST', body: '{}', headers: { 'content-type': 'application/json' },
  });
  assert.equal(reloaded.statusCode, 200);
  assert.equal(JSON.parse(reloaded.body).accounts.find((account) => account.name === 'a').state, 'READY');
});

test('Control API Upgrade requests receive exact 426 without reaching upstream', async (t) => {
  let upstreamCalls = 0;
  const upstream = await startHttpServer(t, (_req, res) => { upstreamCalls += 1; res.end(); });
  const { proxy } = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const { port } = proxy.server.address();
  const raw = await new Promise((resolve, reject) => {
    const socket = net.connect(port, '127.0.0.1', () => {
      socket.write('GET /_proxy/status HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
    });
    const chunks = [];
    socket.on('data', (chunk) => chunks.push(chunk));
    socket.on('end', () => resolve(Buffer.concat(chunks).toString('latin1')));
    socket.on('error', reject);
  });
  assert.equal(raw, 'HTTP/1.1 426 Upgrade Required\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  assert.equal(upstreamCalls, 0);
});

test('absolute-form request targets are rejected before upstream', async (t) => {
  let upstreamCalls = 0;
  const upstream = await startHttpServer(t, (_req, res) => { upstreamCalls += 1; res.end(); });
  const { proxy } = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const response = await new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1', port: proxy.server.address().port,
      method: 'GET', path: 'http://attacker.invalid/backend-api/codex/models',
    }, async (res) => {
      const chunks = [];
      for await (const chunk of res) chunks.push(chunk);
      resolve({ statusCode: res.statusCode, body: Buffer.concat(chunks) });
    });
    req.once('error', reject);
    req.end();
  });
  assert.equal(response.statusCode, 400);
  assert.equal(upstreamCalls, 0);
});
