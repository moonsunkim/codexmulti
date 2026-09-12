import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocketMessages } from '../src/websocket-frames.mjs';
import { serverFrame } from './responses-websocket-helpers.mjs';

test('WebSocket messages decode split headers, masked fragments and interleaved ping frames', () => {
  const body = Buffer.from('{"type":"response.create","input":"안녕"}');
  const wire = Buffer.concat([
    serverFrame(body.subarray(0, 13), { masked: true, fin: false }),
    serverFrame(Buffer.from('ping'), { opcode: 9, masked: true }),
    serverFrame(body.subarray(13), { opcode: 0, masked: true }),
  ]);
  for (let split = 1; split < wire.length; split += 1) {
    const reader = new WebSocketMessages(1024);
    const messages = [...reader.push(wire.subarray(0, split)), ...reader.push(wire.subarray(split))];
    assert.deepEqual(messages.map(({ opcode }) => opcode), [9, 1]);
    assert.equal(messages[0].payload.toString(), 'ping');
    assert.deepEqual(messages[1].payload, body);
  }
});

test('WebSocket frame and fragmented-message limits reject excessive lengths before buffering bodies', () => {
  const huge = Buffer.from([0x81, 127, 0, 0, 0, 1, 0, 0, 0, 0]);
  assert.throws(() => new WebSocketMessages(1024).push(huge), /too_large/);
  const reader = new WebSocketMessages(5);
  reader.push(serverFrame(Buffer.from('1234'), { fin: false }));
  assert.throws(() => reader.push(serverFrame(Buffer.from('56'), { opcode: 0 })), /too_large/);
});

test('compressed and invalid continuation frames are rejected without decoding arbitrary data', () => {
  assert.throws(() => new WebSocketMessages(1024).push(Buffer.from([0xc1, 0])), /extensions/);
  assert.throws(() => new WebSocketMessages(1024).push(Buffer.from([0x80, 0])), /data_frame/);
});
