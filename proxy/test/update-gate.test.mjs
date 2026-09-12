import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';
import { UpdateGate } from '../src/update-gate.mjs';
import { request, sseOk, startHttpServer, startTestProxy, syntheticAuth } from './helpers.mjs';

const transactionId = '11111111-2222-4333-8444-555555555555';
function policy(overrides = {}) {
  return {
    runtimeId: 'a'.repeat(64), verified: true, generation: 1,
    configRevision: () => 'b'.repeat(64),
    authorize: (_action, body) => {
      if (body.transaction_id !== transactionId || body.epoch !== 1) throw new Error('transaction_mismatch');
    },
    canResume: () => true, stopCommitted: () => false, canActivate: () => false,
    ...overrides,
  };
}
function identity(gate, extras = {}) {
  return { transaction_id: transactionId, epoch: 1, boot_id: gate.bootId,
    runtime_id: gate.context.runtimeId, config_revision: gate.context.configRevision(), ...extras };
}
async function post(started, action, extras = {}) {
  const response = await request(started.origin, `/_proxy/update/v1/${action}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(identity(started.proxy.updateGate, extras)),
  });
  return { status: response.statusCode, body: JSON.parse(response.body) };
}

test('prepare counts a partial HTTP body, preserves its response, then fences new data and writers', async (t) => {
  let client;
  t.after(() => client?.destroy());
  let upstreamCalls = 0;
  const upstream = await startHttpServer(t, (req, res) => {
    upstreamCalls += 1;
    req.resume();
    req.on('end', () => res.writeHead(200, { 'content-type': 'text/event-stream' }).end(sseOk()));
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin,
    options: { updateContext: policy() } });
  const body = '{"input":"slow arriving body"}';
  const received = once(started.proxy.server, 'request');
  const completion = new Promise((resolve, reject) => {
    client = http.request(`${started.origin}/backend-api/codex/responses`, {
      method: 'POST', headers: { 'content-length': Buffer.byteLength(body) },
    }, async (res) => {
      const chunks = [];
      for await (const chunk of res) chunks.push(chunk);
      resolve({ status: res.statusCode, text: Buffer.concat(chunks).toString() });
    });
    client.on('error', reject);
    client.write(body.slice(0, 8));
  });
  await received;
  assert.equal((await started.proxy.statusPayload()).in_flight, 1);
  const busy = await post(started, 'prepare-if-idle');
  assert.equal(busy.status, 409);
  assert.equal(busy.body.work.http, 1);
  assert.equal(busy.body.gate, 'serving');
  client.end(body.slice(8));
  const completed = await completion;
  assert.equal(completed.status, 200);
  assert.match(completed.text, /response.completed/);
  await started.proxy.updateGate.whenIdle();
  const ready = await post(started, 'prepare-if-idle');
  assert.equal(ready.status, 200);
  assert.equal(ready.body.gate, 'quiescent');
  const blocked = await request(started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  assert.equal(blocked.statusCode, 503);
  const mutation = await request(started.origin, '/_proxy/accounts/a/pause', { method: 'POST', body: '{}' });
  assert.equal(mutation.statusCode, 503);
  assert.equal(upstreamCalls, 1);
  assert.equal((await post(started, 'abort-prepare', { lease: ready.body.lease })).status, 200);
});

test('an open quiet WebSocket keeps the proxy busy for the whole connection', async (t) => {
  const sockets = new Set();
  t.after(() => { for (const socket of sockets) socket.destroy(); });
  const upstream = await startHttpServer(t, (_req, res) => res.end());
  upstream.server.on('upgrade', (_req, socket) => {
    sockets.add(socket);
    socket.on('end', () => socket.end());
    socket.on('error', () => {});
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n');
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin,
    options: { updateContext: policy() } });
  const url = new URL(started.origin);
  const client = net.connect(Number(url.port), '127.0.0.1');
  sockets.add(client);
  await once(client, 'connect');
  client.write(`GET /backend-api/codex/responses HTTP/1.1\r\nHost: ${url.host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: c3ludGhldGljLWtleQ==\r\n\r\n`);
  const [head] = await once(client, 'data');
  assert.match(head.toString(), /101 Switching Protocols/);
  const busy = await post(started, 'prepare-if-idle');
  assert.equal(busy.status, 409);
  assert.equal(busy.body.work.websocket, 1);
  client.end();
  await once(client, 'close');
  await started.proxy.updateGate.whenIdle();
  assert.equal((await post(started, 'prepare-if-idle')).status, 200);
});

test('proactive OAuth renewal is work until the rotated credential has been stored', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.end());
  let allowRefresh;
  let markStarted;
  const entered = new Promise((resolve) => { markStarted = resolve; });
  const refreshPending = new Promise((resolve) => { allowRefresh = resolve; });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'], now,
    authByName: { a: syntheticAuth('a', now / 1000 + 60) },
    options: { updateContext: policy(), refreshRequest: async () => {
      markStarted();
      await refreshPending;
      return { access_token: syntheticAuth('a', now / 1000 + 100_000).tokens.access_token,
        refresh_token: 'synthetic-rotated-refresh' };
    } } });
  const renewal = started.proxy.runTokenRenewalCycle();
  await entered;
  const busy = await post(started, 'prepare-if-idle');
  assert.equal(busy.status, 409);
  assert.equal(busy.body.work.renewal, 1);
  allowRefresh();
  await renewal;
  assert.match(await readFile(started.accounts[0].auth_file, 'utf8'), /synthetic-rotated-refresh/);
  assert.equal((await post(started, 'prepare-if-idle')).status, 200);
});

test('pure update health and fenced legacy status do not expire or rewrite cooldown state', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin,
    options: { updateContext: policy() } });
  await started.proxy.failover.markCooldown('a', 1000);
  const before = await readFile(started.proxy.config.state_file);
  await request(started.origin, '/_proxy/update/v1/health');
  assert.equal((await post(started, 'prepare-if-idle')).status, 200);
  await request(started.origin, '/_proxy/status');
  assert.deepEqual(await readFile(started.proxy.config.state_file), before);
});

test('expired prepare can reopen only before durable stop, including a lost stop acknowledgement', async () => {
  let now = 0;
  let stopped = false;
  const gate = new UpdateGate({ now: () => now,
    context: policy({ canResume: () => !stopped, stopCommitted: () => stopped }) });
  const first = await gate.command('prepare-if-idle', identity(gate));
  now = 10_001;
  const release = gate.enter('http');
  assert.equal(typeof release, 'function');
  release();
  const second = await gate.command('prepare-if-idle', identity(gate));
  assert.notEqual(first.body.lease, second.body.lease);
  stopped = true;
  now = 30_002;
  assert.equal(gate.enter('http'), null);
  const body = identity(gate, { lease: second.body.lease });
  assert.equal((await gate.command('commit-stop', body)).status, 200);
  assert.equal((await gate.command('commit-stop', body)).status, 200);
  assert.equal((await gate.command('abort-prepare', body)).status, 409);
  assert.equal(gate.mode, 'stopped');
});

test('late epochs, wrong process identity and unknown durable activation cannot open a gate', async () => {
  let committed = false;
  const gate = new UpdateGate({ context: policy({ gated: true, canActivate: () => committed }) });
  const body = identity(gate, { generation: 2 });
  assert.equal((await gate.command('activate', body)).status, 409);
  committed = true;
  assert.equal((await gate.command('activate', { ...body, epoch: 2 })).status, 409);
  assert.equal((await gate.command('activate', { ...body, boot_id: transactionId })).status, 409);
  assert.equal(gate.enter('http'), null);
  assert.equal((await gate.command('activate', body)).status, 200);
  const release = gate.enter('http');
  assert.equal((await gate.command('activate', body)).status, 200);
  assert.equal(gate.total(), 1);
  release();
});

test('control authentication is still required for update commands', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin,
    options: { updateContext: policy() } });
  const response = await request(started.origin, '/_proxy/update/v1/prepare-if-idle', {
    method: 'POST', controlAuth: false, headers: { 'content-type': 'application/json' },
    body: JSON.stringify(identity(started.proxy.updateGate)),
  });
  assert.equal(response.statusCode, 401);
  assert.equal(started.proxy.updateGate.mode, 'serving');
});
