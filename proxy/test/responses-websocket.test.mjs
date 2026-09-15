import test from 'node:test';
import assert from 'node:assert/strict';
import { gzipSync } from 'node:zlib';
import { request } from './helpers.mjs';
import { completed, responsesFixture, serverFrame, usageLimit } from './responses-websocket-helpers.mjs';

test('an in-band WebSocket usage limit retries the next account without surfacing the rejected request', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    send(name === 'a' ? usageLimit(event) : completed('response-b', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  const event = { type: 'response.create', model: 'synthetic', input: [{ role: 'user', content: 'hello' }] };
  client.send(event);
  assert.equal((await client.next()).type, 'response.completed');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'b']);
  assert.deepEqual(fixture.calls[1].event, event);
  assert.equal(fixture.proxy.failover.stateOf('a'), 'COOLDOWN');
});

test('manual switching routes the next response on an existing client socket to the selected account', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send }) => send(completed(`response-${name}`, event)), {
    accountNames: ['a', 'b'],
  });
  const client = await fixture.connect();
  client.send({ type: 'response.create', model: 'synthetic', input: [{ role: 'user', content: 'first' }] });
  assert.equal((await client.next()).response.id, 'response-a');
  const switched = await request(fixture.origin, '/_proxy/switch', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'b' }),
  });
  assert.equal(switched.statusCode, 200);
  client.send({ type: 'response.create', model: 'synthetic', input: [{ role: 'user', content: 'second' }] });
  assert.equal((await client.next()).response.id, 'response-b');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'b']);
});

test('account failover restores the full input and completed output for a chained response', async (t) => {
  const firstInput = [{ role: 'user', content: 'first context' }];
  const output = [{ type: 'reasoning', id: 'reasoning-1', encrypted_content: 'synthetic-encrypted' }, {
    type: 'function_call', id: 'item-1', call_id: 'call-1', name: 'synthetic_tool', arguments: '{}',
  }];
  const nextInput = [{ type: 'function_call_output', call_id: 'call-1', output: 'result' }];
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    if (!event.previous_response_id && name === 'a') send(completed('response-first', event, output));
    else if (name === 'a') send(usageLimit(event));
    else send(completed('response-next', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', model: 'synthetic', input: firstInput });
  assert.equal((await client.next()).response.id, 'response-first');
  client.send({ type: 'response.create', model: 'synthetic', previous_response_id: 'response-first', input: nextInput });
  assert.equal((await client.next()).response.id, 'response-next');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'a', 'b']);
  assert.equal(fixture.calls[2].event.previous_response_id, null);
  assert.deepEqual(fixture.calls[2].event.input, [...firstInput, ...output, ...nextInput]);
});

test('manual switching preserves a running response and changes accounts on its next turn', async (t) => {
  let finish;
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    if (name === 'a') {
      send({ type: 'response.created', response: { id: 'running-a' } });
      send({ type: 'response.output_text.delta', response_id: 'running-a', delta: 'already generated' });
      finish = () => send(completed('running-a', event));
    } else send(completed('next-b', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.equal((await client.next()).type, 'response.created');
  assert.equal((await client.next()).delta, 'already generated');
  await fixture.proxy.failover.switchTo('b');
  assert.equal(fixture.connections[0].socket.destroyed, false);
  finish();
  assert.equal((await client.next()).response.id, 'running-a');
  client.send({ type: 'response.create', previous_response_id: 'running-a', input: [] });
  assert.equal((await client.next()).response.id, 'next-b');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'b']);
});

test('a usage limit after response output is not replayed on another account', async (t) => {
  const fixture = await responsesFixture(t, ({ event, send }) => {
    send({ type: 'response.output_text.delta', delta: 'keep this output' });
    send(usageLimit(event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.equal((await client.next()).delta, 'keep this output');
  assert.equal((await client.next()).error.type, 'usage_limit_reached');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a']);
  assert.equal(fixture.proxy.failover.stateOf('a'), 'COOLDOWN');
});

test('in-band usage limits visit each eligible account once and surface exhaustion', async (t) => {
  const fixture = await responsesFixture(t, ({ event, send }) => send(usageLimit(event)), {
    accountNames: ['a', 'b', 'c'],
  });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.equal((await client.next()).error.type, 'usage_limit_reached');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'b', 'c']);
  for (const name of ['a', 'b', 'c']) assert.equal(fixture.proxy.failover.stateOf(name), 'COOLDOWN');
});

test('fragmented WebSocket usage errors retry without forwarding any error fragment', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send, socket }) => {
    if (name === 'b') return send(completed('fragment-recovered', event));
    const body = Buffer.from(JSON.stringify(usageLimit(event)));
    const first = serverFrame(body.subarray(0, 17), { fin: false });
    const last = serverFrame(body.subarray(17), { opcode: 0 });
    socket.write(first.subarray(0, 1));
    socket.write(first.subarray(1));
    socket.write(serverFrame(Buffer.from('ping'), { opcode: 9 }));
    socket.write(last);
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  const body = Buffer.from(JSON.stringify({ type: 'response.create', input: [] }));
  client.socket.write(serverFrame(body.subarray(0, 11), { masked: true, fin: false }));
  client.socket.write(serverFrame(body.subarray(11), { masked: true, opcode: 0 }));
  assert.equal((await client.next()).response.id, 'fragment-recovered');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'b']);
});

test('a failed named lane can move accounts while another lane keeps streaming', async (t) => {
  let finishRunning;
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    if (event.stream_id === 'running') {
      send({ type: 'response.created', stream_id: 'running', response: { id: 'parallel-running' } });
      finishRunning = () => send(completed('parallel-running', event));
    } else send(name === 'a' ? usageLimit(event) : completed('parallel-recovered', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', stream_id: 'running', input: [] });
  assert.equal((await client.next()).stream_id, 'running');
  client.send({ type: 'response.create', stream_id: 'limited', input: [] });
  assert.equal((await client.next()).response.id, 'parallel-recovered');
  assert.equal(fixture.connections[0].socket.destroyed, false);
  finishRunning();
  assert.equal((await client.next()).response.id, 'parallel-running');
  assert.deepEqual(fixture.calls.map(({ name, event }) => [name, event.stream_id]), [
    ['a', 'running'], ['a', 'limited'], ['b', 'limited'],
  ]);
});

test('queued requests in one lane remain ordered across failover', async (t) => {
  let rejectFirst;
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    if (name === 'a') rejectFirst = () => send(usageLimit(event));
    else send(completed(event.metadata.key, event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [], metadata: { key: 'first' } });
  client.send({ type: 'response.create', input: [], metadata: { key: 'second' } });
  const deadline = Date.now() + 1000;
  while (!rejectFirst && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 5));
  assert.ok(rejectFirst);
  rejectFirst();
  assert.equal((await client.next()).response.id, 'first');
  assert.equal((await client.next()).response.id, 'second');
  assert.deepEqual(fixture.calls.map(({ name, event }) => [name, event.metadata.key]), [
    ['a', 'first'], ['b', 'first'], ['b', 'second'],
  ]);
});

test('unrelated WebSocket errors do not switch accounts', async (t) => {
  const failure = { type: 'error', status: 400, error: { type: 'invalid_request_error' } };
  const fixture = await responsesFixture(t, ({ send }) => send(failure), { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.deepEqual(await client.next(), failure);
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a']);
  assert.equal(fixture.proxy.failover.stateOf('a'), 'READY');
});

test('cancellation before a usage error prevents replay', async (t) => {
  const fixture = await responsesFixture(t, ({ event, send }) => {
    if (event.type === 'response.cancel') send(usageLimit(event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  client.send({ type: 'response.cancel' });
  assert.equal((await client.next()).error.type, 'usage_limit_reached');
  assert.deepEqual(fixture.calls.map(({ name, event }) => [name, event.type]), [
    ['a', 'response.create'], ['a', 'response.cancel'],
  ]);
});

test('a usage error followed immediately by upstream close still fails over', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send, socket }) => {
    if (name === 'a') socket.end(serverFrame(usageLimit(event)));
    else send(completed('closed-recovered', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.equal((await client.next()).response.id, 'closed-recovered');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'b']);
});

test('late terminal events from a rejected account do not leak into the retried response', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send, socket }) => {
    if (name === 'a') {
      socket.write(Buffer.concat([serverFrame(usageLimit(event)), serverFrame(completed('late-old-response', event))]));
    } else send(completed('only-new-response', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.equal((await client.next()).response.id, 'only-new-response');
});

test('unknown mid-response input invalidates cached context instead of dropping it during account switching', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    if (event.type === 'response.input.append') send(completed('steered-response', event));
    else if (name === 'b') send(completed('unsafe-context', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [{ role: 'user', content: 'initial' }] });
  client.send({ type: 'response.input.append', input: [{ role: 'user', content: 'must preserve' }] });
  assert.equal((await client.next()).response.id, 'steered-response');
  await fixture.proxy.failover.switchTo('b');
  client.send({ type: 'response.create', previous_response_id: 'steered-response', input: [] });
  assert.equal((await client.next()).error.code, 'previous_response_not_found');
  assert.deepEqual(fixture.calls.map(({ name }) => name), ['a', 'a']);
});

test('large multibyte input survives a WebSocket failover byte for byte', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    send(name === 'a' ? usageLimit(event) : completed('large-input', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  const event = { type: 'response.create', input: [{ role: 'user', content: '한국어🙂'.repeat(12000) }] };
  client.send(event);
  assert.equal((await client.next()).response.id, 'large-input');
  assert.deepEqual(fixture.calls[0].event, event);
  assert.deepEqual(fixture.calls[1].event, event);
});

test('context eviction asks the client for full input instead of sending a truncated conversation', async (t) => {
  let serial = 0;
  const fixture = await responsesFixture(t, ({ event, send }) => send(completed(`bounded-${serial += 1}`, event)), {
    accountNames: ['a', 'b'], config: { request_body_limit_bytes: 700 },
  });
  const client = await fixture.connect();
  let previous;
  for (let index = 0; index < 4; index += 1) {
    client.send({ type: 'response.create', previous_response_id: previous, input: [{ role: 'user', content: 'x'.repeat(200) }] });
    previous = (await client.next()).response.id;
  }
  await fixture.proxy.failover.switchTo('b');
  client.send({ type: 'response.create', previous_response_id: previous, input: [] });
  assert.equal((await client.next()).error.code, 'previous_response_not_found');
  assert.equal(fixture.calls.length, 4);
});

test('a cross-lane continuation carries its source context when the selected account changes', async (t) => {
  const original = [{ role: 'user', content: 'shared parent' }];
  const fixture = await responsesFixture(t, ({ name, event, send }) => send(completed(`fork-${name}`, event)), {
    accountNames: ['a', 'b'],
  });
  const client = await fixture.connect();
  client.send({ type: 'response.create', stream_id: 'parent', input: original });
  assert.equal((await client.next()).response.id, 'fork-a');
  await fixture.proxy.failover.switchTo('b');
  client.send({ type: 'response.create', stream_id: 'child', previous_response_id: 'fork-a', input: [] });
  assert.equal((await client.next()).response.id, 'fork-b');
  assert.equal(fixture.calls[1].event.stream_id, 'child');
  assert.equal(fixture.calls[1].event.previous_response_id, null);
  assert.deepEqual(fixture.calls[1].event.input, original);
});

test('failover also skips a compressed usage-limit response during the replacement handshake', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    send(name === 'a' ? usageLimit(event) : completed('third-account', event));
  }, {
    accountNames: ['a', 'b', 'c'],
    handshake: ({ name, socket }) => {
      if (name !== 'b') return true;
      const body = gzipSync(Buffer.from(JSON.stringify(usageLimit())));
      socket.end(Buffer.concat([Buffer.from(`HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nContent-Encoding: gzip\r\nContent-Length: ${body.length}\r\n\r\n`), body]));
      return false;
    },
  });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  assert.equal((await client.next()).response.id, 'third-account');
  assert.deepEqual(fixture.connections.map(({ name }) => name), ['a', 'b', 'c']);
  assert.equal(fixture.proxy.failover.stateOf('b'), 'COOLDOWN');
});

test('closing a client releases all upstream connections after a replacement handshake falls back to an existing account', async (t) => {
  let finishFirst;
  const fixture = await responsesFixture(t, ({ event, send }) => {
    if (event.stream_id === 'first') {
      send({ type: 'response.created', stream_id: 'first', response: { id: 'first' } });
      finishFirst = () => send(completed('first', event));
    } else send(completed('second', event));
  }, {
    accountNames: ['a', 'b'],
    handshake: ({ name, socket }) => {
      if (name !== 'b') return true;
      const body = Buffer.from(JSON.stringify(usageLimit()));
      socket.end(Buffer.concat([Buffer.from(`HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\n\r\n`), body]));
      return false;
    },
  });
  const client = await fixture.connect();
  client.send({ type: 'response.create', stream_id: 'first', input: [] });
  await client.next();
  await fixture.proxy.failover.switchTo('b');
  client.send({ type: 'response.create', stream_id: 'second', input: [] });
  assert.equal((await client.next()).response.id, 'second');
  finishFirst();
  assert.equal((await client.next()).response.id, 'first');
  assert.deepEqual(fixture.connections.map(({ name }) => name), ['a', 'b', 'a']);
  client.socket.destroy();
  let inFlight = -1;
  const deadline = Date.now() + 1000;
  while (Date.now() < deadline) {
    inFlight = JSON.parse((await request(fixture.origin, '/_proxy/status')).body).in_flight;
    if (inFlight === 0) break;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.equal(inFlight, 0);
});


test('status counts response work rather than idle WebSocket connections', async (t) => {
  let finish;
  const fixture = await responsesFixture(t, ({ event, send }) => {
    send({ type: 'response.created', response: { id: 'working' } });
    finish = () => send(completed('working', event));
  }, { accountNames: ['a'] });
  const client = await fixture.connect();
  const status = async () => JSON.parse((await request(fixture.origin, '/_proxy/status')).body);
  assert.equal((await status()).in_flight, 0);
  assert.equal((await status()).accounts[0].in_flight, 0);
  client.send({ type: 'response.create', input: [] });
  await client.next();
  assert.equal((await status()).in_flight, 1);
  assert.equal((await status()).accounts[0].in_flight, 1);
  finish();
  await client.next();
  assert.equal((await status()).in_flight, 0);
  assert.equal((await status()).accounts[0].in_flight, 0);
  assert.equal(client.socket.destroyed, false);
});

test('status counts queued responses and clears all work when a client disconnects', async (t) => {
  const fixture = await responsesFixture(t, ({ send }) => {
    send({ type: 'response.created', response: { id: 'pending' } });
  }, { accountNames: ['a'] });
  const client = await fixture.connect();
  const status = async () => JSON.parse((await request(fixture.origin, '/_proxy/status')).body);
  client.send({ type: 'response.create', input: [] });
  await client.next();
  client.send({ type: 'response.create', input: [] });
  for (let i = 0; i < 100 && (await status()).in_flight !== 2; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.equal((await status()).in_flight, 2);
  assert.equal((await status()).accounts[0].in_flight, 1);
  client.socket.destroy();
  for (let i = 0; i < 100 && (await status()).in_flight !== 0; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.equal((await status()).in_flight, 0);
  assert.equal((await status()).accounts[0].in_flight, 0);
});

test('failover retires completed work while retaining idle account connections', async (t) => {
  const fixture = await responsesFixture(t, ({ name, event, send }) => {
    send(name === 'a' ? usageLimit(event) : completed('done-b', event));
  }, { accountNames: ['a', 'b'] });
  const client = await fixture.connect();
  client.send({ type: 'response.create', input: [] });
  await client.next();
  const status = JSON.parse((await request(fixture.origin, '/_proxy/status')).body);
  assert.equal(status.in_flight, 0);
  assert.deepEqual(status.accounts.map((account) => account.in_flight), [0, 0]);
  assert.equal(fixture.connections.length, 2);
});

for (const type of ['error', 'response.failed', 'response.incomplete']) {
  test(`${type} clears request counts without requiring the WebSocket to close`, async (t) => {
    const fixture = await responsesFixture(t, ({ send }) => {
      send(type === 'error' ? { type, status: 400, error: { type: 'invalid_request_error' } }
        : { type, response: { id: 'failed' } });
    }, { accountNames: ['a'] });
    const client = await fixture.connect();
    client.send({ type: 'response.create', input: [] });
    assert.equal((await client.next()).type, type);
    const status = JSON.parse((await request(fixture.origin, '/_proxy/status')).body);
    assert.equal(status.in_flight, 0);
    assert.equal(status.accounts[0].in_flight, 0);
  });
}
