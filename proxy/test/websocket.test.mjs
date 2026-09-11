import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { once } from 'node:events';
import {
  startHttpServer,
  startTestProxy,
} from './helpers.mjs';

function selectedName(req) {
  const token = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
  try {
    return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()).token_name;
  } catch {
    return null;
  }
}

function requestHead(origin, requestPath, headers = {}) {
  const url = new URL(origin);
  return [
    `GET ${requestPath} HTTP/1.1`,
    `Host: ${url.host}`,
    'Connection: Upgrade',
    'Upgrade: websocket',
    'Sec-WebSocket-Key: c3ludGhldGljLWtleQ==',
    'Sec-WebSocket-Version: 13',
    ...Object.entries(headers).map(([name, value]) => `${name}: ${value}`),
    '',
    '',
  ].join('\r\n');
}

async function openWebSocket(origin, requestPath, headers = {}) {
  const url = new URL(origin);
  return await new Promise((resolve, reject) => {
    const socket = net.connect(Number(url.port), url.hostname);
    let raw = Buffer.alloc(0);
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      reject(error);
    };
    const onData = (chunk) => {
      raw = Buffer.concat([raw, chunk]);
      const end = raw.indexOf('\r\n\r\n');
      if (end === -1) return;
      settled = true;
      socket.off('data', onData);
      socket.off('error', fail);
      socket.off('end', onEnd);
      resolve({
        socket,
        header: raw.subarray(0, end + 4).toString('latin1'),
        head: raw.subarray(end + 4),
      });
    };
    const onEnd = () => fail(new Error('upgrade_ended_before_headers'));
    socket.on('data', onData);
    socket.once('error', fail);
    socket.once('end', onEnd);
    socket.once('connect', () => socket.write(requestHead(origin, requestPath, headers)));
  });
}

async function rawUpgrade(origin, requestPath, headers = {}) {
  const url = new URL(origin);
  return await new Promise((resolve, reject) => {
    const socket = net.connect(Number(url.port), url.hostname);
    const chunks = [];
    socket.on('data', (chunk) => chunks.push(chunk));
    socket.once('error', reject);
    socket.once('end', () => resolve(Buffer.concat(chunks).toString('latin1')));
    socket.once('connect', () => socket.write(requestHead(origin, requestPath, headers)));
  });
}

function handleUpgrades(testContext, server, handler) {
  const sockets = new Set();
  server.on('upgrade', (req, socket, head) => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    socket.once('end', () => socket.destroy());
    socket.once('error', () => socket.destroy());
    handler(req, socket, head);
  });
  testContext.after(() => {
    for (const socket of sockets) socket.destroy();
  });
}

function accept(socket) {
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: synthetic\r\n\r\n');
}

async function readExactly(socket, initial, length) {
  let buffer = initial;
  while (buffer.length < length) {
    const [chunk] = await once(socket, 'data');
    buffer = Buffer.concat([buffer, chunk]);
  }
  return buffer.subarray(0, length);
}

async function destroySocket(socket) {
  if (socket.destroyed) return;
  const closed = once(socket, 'close');
  socket.end();
  await closed;
}

async function waitFor(predicate) {
  const deadline = Date.now() + 1000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error('condition_not_met');
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

test('WebSocket upgrade relays the 101 handshake and raw bytes in both directions', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(400).end());
  handleUpgrades(t, upstream.server, (_req, socket, head) => {
    accept(socket);
    if (head.length) socket.write(head);
    socket.on('data', (chunk) => socket.write(chunk));
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const opened = await openWebSocket(started.origin, '/backend-api/codex/responses');
  t.after(() => opened.socket.destroy());
  assert.match(opened.header, /^HTTP\/1\.1 101 Switching Protocols\r\n/);
  const payload = Buffer.from([0x81, 0x02, 0x6f, 0x6b]);
  const echoed = readExactly(opened.socket, opened.head, payload.length);
  opened.socket.write(payload);
  assert.deepEqual(await echoed, payload);
  await destroySocket(opened.socket);
});

test('WebSocket upstream handshake uses the active account credentials', async (t) => {
  let received;
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(400).end());
  handleUpgrades(t, upstream.server, (req, socket) => {
    received = req.headers;
    accept(socket);
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a', 'b'] });
  await started.proxy.failover.switchTo('b');
  const opened = await openWebSocket(started.origin, '/backend-api/codex/responses', {
    Authorization: 'Bearer inbound-secret',
    Cookie: 'session=inbound-secret',
  });
  t.after(() => opened.socket.destroy());
  assert.match(opened.header, /^HTTP\/1\.1 101 Switching Protocols\r\n/);
  assert.equal(selectedName({ headers: received }), 'b');
  assert.equal(received['chatgpt-account-id'], 'synthetic-account-b');
  assert.notEqual(received.authorization, 'Bearer inbound-secret');
  await destroySocket(opened.socket);
});

test('WebSocket usage-limit handshake retries the next account exactly once', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const calls = [];
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(400).end());
  handleUpgrades(t, upstream.server, (req, socket) => {
    const name = selectedName(req);
    calls.push(name);
    if (name === 'a') {
      const body = Buffer.from(JSON.stringify({
        error: { type: 'usage_limit_reached', resets_at: Math.floor(now / 1000) + 120 },
      }));
      socket.end(`HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`);
      return;
    }
    accept(socket);
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b', 'c'],
    now,
  });
  const opened = await openWebSocket(started.origin, '/backend-api/codex/responses');
  t.after(() => opened.socket.destroy());
  assert.match(opened.header, /^HTTP\/1\.1 101 Switching Protocols\r\n/);
  assert.deepEqual(calls, ['a', 'b']);
  assert.equal(started.proxy.failover.stateOf('a'), 'COOLDOWN');
  await destroySocket(opened.socket);
});

test('WebSocket non-usage handshake error is relayed without retry', async (t) => {
  const calls = [];
  const body = 'synthetic unavailable';
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(400).end());
  handleUpgrades(t, upstream.server, (req, socket) => {
    calls.push(selectedName(req));
    socket.end(`HTTP/1.1 503 Service Unavailable\r\nContent-Type: text/plain\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`);
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b'],
  });
  const raw = await rawUpgrade(started.origin, '/backend-api/codex/responses');
  assert.match(raw, /^HTTP\/1\.1 503 Service Unavailable\r\n/);
  assert.match(raw, /\r\n\r\nsynthetic unavailable$/);
  assert.deepEqual(calls, ['a']);
});

test('WebSocket logs open and close with duration and directional byte counts only', async (t) => {
  const events = [];
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(400).end());
  handleUpgrades(t, upstream.server, (_req, socket) => {
    accept(socket);
    socket.on('data', (chunk) => socket.write(chunk));
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { logger: (event) => events.push(event) },
  });
  const opened = await openWebSocket(
    started.origin,
    '/backend-api/codex/responses?access_token=must-not-log',
    { Authorization: 'Bearer must-not-log', Cookie: 'session=must-not-log' },
  );
  t.after(() => opened.socket.destroy());
  assert.match(opened.header, /^HTTP\/1\.1 101 Switching Protocols\r\n/);
  const payload = Buffer.from('synthetic-frame');
  const echoed = readExactly(opened.socket, opened.head, payload.length);
  opened.socket.write(payload);
  assert.deepEqual(await echoed, payload);
  await destroySocket(opened.socket);
  await waitFor(() => events.some(({ event }) => event === 'ws_close'));
  const openedEvent = events.find(({ event }) => event === 'ws_open');
  const closedEvent = events.find(({ event }) => event === 'ws_close');
  assert.ok(openedEvent);
  assert.ok(closedEvent);
  assert.equal(closedEvent.client_to_upstream_bytes, payload.length);
  assert.equal(closedEvent.upstream_to_client_bytes, payload.length);
  assert.equal(Number.isInteger(closedEvent.duration_ms), true);
  assert.doesNotMatch(JSON.stringify(events), /must-not-log|authorization|cookie|access_token/i);
});
