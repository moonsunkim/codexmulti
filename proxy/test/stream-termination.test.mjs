import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { AccountState } from '../src/failover.mjs';
import { startHttpServer, startTestProxy } from './helpers.mjs';

async function readIncoming(request) {
  for await (const _chunk of request) {

  }
}

async function waitFor(predicate, description, timeoutMs = 2_000) {
  const deadline = Date.now() + timeoutMs;
  while (!await predicate()) {
    if (Date.now() >= deadline) throw new Error(`timed_out_waiting_for_${description}`);
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

async function closeClientWhen(origin, predicate) {
  return await new Promise((resolve, reject) => {
    let settled = false;
    let received = '';
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    const request = http.request(`${origin}/backend-api/codex/responses`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': '2' },
    }, (response) => {
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        received += chunk;
        if (!predicate(received)) return;
        response.socket.destroy();
        finish({ response, received });
      });
      response.once('error', (error) => {
        if (!settled) reject(error);
      });
      response.once('end', () => {
        if (!settled) reject(new Error('response_ended_before_client_close'));
      });
    });
    request.once('error', (error) => {
      if (!settled) reject(error);
    });
    request.end('{}');
  });
}

async function requestUntilUpstreamBreak(origin) {
  return await new Promise((resolve, reject) => {
    let responseSeen = false;
    const request = http.request(`${origin}/backend-api/codex/responses`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': '2' },
    }, (response) => {
      responseSeen = true;
      response.resume();
      const finish = () => resolve({
        destroyed: response.destroyed,
        complete: response.complete,
      });
      response.once('aborted', finish);
      response.once('error', finish);
      response.once('close', finish);
      response.once('end', () => reject(new Error('downstream_ended_cleanly')));
    });
    request.once('error', (error) => {
      if (responseSeen) resolve({ destroyed: true, complete: false });
      else reject(error);
    });
    request.end('{}');
  });
}

test('T1 completed SSE followed by client close is logged as terminal client_closed', { timeout: 10_000 }, async (t) => {
  const events = [];
  let upstreamDestroyed = false;
  const upstream = await startHttpServer(t, async (request, response) => {
    await readIncoming(request);
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.once('close', () => {
      upstreamDestroyed = !response.writableEnded;
    });
    response.write('event: response.com');
    await new Promise((resolve) => setImmediate(resolve));
    const completed = JSON.stringify({
      type: 'response.completed',
      response: { output: [{ type: 'message', content: 'x'.repeat(10 * 1024) }] },
    });
    response.write(`pleted\ndata: ${completed}\n\n`);
    await new Promise((resolve) => setTimeout(resolve, 300));
    if (!response.destroyed) response.end();
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { logger: (event) => events.push(event) },
  });

  const client = await closeClientWhen(started.origin,
    (received) => received.includes('response.completed') && received.endsWith('\n\n'));
  assert.ok(Buffer.byteLength(client.received) > 8 * 1024);
  await waitFor(() => events.some(({ event }) => event === 'client_closed' || event === 'request_error'), 'termination_log');
  await waitFor(() => upstreamDestroyed, 'upstream_destroy');
  await waitFor(() => started.proxy.statusPayload().then(({ in_flight }) => in_flight === 0), 'in_flight_zero');

  const closed = events.filter(({ event }) => event === 'client_closed');
  assert.equal(events.some(({ event }) => event === 'request_error'), false);
  assert.equal(closed.length, 1);
  assert.equal(closed[0].terminal_seen, true);
  assert.ok(closed[0].relayed_bytes > 0);
  assert.deepEqual(Object.keys(closed[0]).sort(), [
    'account_name', 'attempt', 'duration_ms', 'event', 'level', 'method',
    'relayed_bytes', 'request_id', 'route', 'terminal_seen', 'timestamp', 'upstream_status',
  ]);
  assert.equal(upstreamDestroyed, true);
  assert.equal((await started.proxy.statusPayload()).in_flight, 0);
});

test('T2 client close before terminal SSE is logged as nonterminal client_closed', { timeout: 10_000 }, async (t) => {
  const events = [];
  const upstream = await startHttpServer(t, async (request, response) => {
    await readIncoming(request);
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.write('event: response.created\ndata: {"type":"response.created"}\n\n');
    await new Promise((resolve) => setTimeout(resolve, 300));
    if (!response.destroyed) {
      response.end('event: response.completed\ndata: {"type":"response.completed"}\n\n');
    }
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { logger: (event) => events.push(event) },
  });

  await closeClientWhen(started.origin, (received) => received.includes('response.created'));
  await waitFor(() => events.some(({ event }) => event === 'client_closed' || event === 'request_error'), 'termination_log');

  const closed = events.filter(({ event }) => event === 'client_closed');
  assert.equal(events.some(({ event }) => event === 'request_error'), false);
  assert.equal(closed.length, 1);
  assert.equal(closed[0].terminal_seen, false);
});

test('T3 upstream break after 200 is logged as upstream_stream_error and keeps account READY', { timeout: 10_000 }, async (t) => {
  const events = [];
  const upstream = await startHttpServer(t, async (request, response) => {
    await readIncoming(request);
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.write('event: response.created\ndata: {"type":"response.created"}\n\n');
    await new Promise((resolve) => setImmediate(resolve));
    response.socket.destroy();
  });
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { logger: (event) => events.push(event) },
  });

  const downstream = await requestUntilUpstreamBreak(started.origin);
  await waitFor(() => events.some(({ event }) => event === 'upstream_stream_error' || event === 'request_error'), 'stream_error_log');

  const streamErrors = events.filter(({ event }) => event === 'upstream_stream_error');
  assert.equal(events.some(({ event }) => event === 'request_error'), false);
  assert.equal(streamErrors.length, 1);
  assert.equal(streamErrors[0].level, 'error');
  assert.equal(typeof streamErrors[0].error_code, 'string');
  assert.ok(streamErrors[0].error_code.length > 0);
  assert.deepEqual(Object.keys(streamErrors[0]).sort(), [
    'account_name', 'attempt', 'duration_ms', 'error_code', 'event', 'level',
    'method', 'relayed_bytes', 'request_id', 'route', 'timestamp', 'upstream_status',
  ]);
  assert.equal(downstream.destroyed, true);
  assert.equal(downstream.complete, false);
  assert.equal(started.proxy.failover.stateOf('a'), AccountState.READY);
});
