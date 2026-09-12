import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import net from 'node:net';
import { startHttpServer, startTestProxy } from './helpers.mjs';

export function serverFrame(value, { opcode = 1, fin = true, masked = false } = {}) {
  const payload = Buffer.isBuffer(value) ? value : Buffer.from(JSON.stringify(value));
  let header;
  if (payload.length < 126) {
    header = Buffer.from([(fin ? 0x80 : 0) | opcode, payload.length]);
  } else if (payload.length <= 65535) {
    header = Buffer.alloc(4);
    header[0] = (fin ? 0x80 : 0) | opcode;
    header[1] = 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = (fin ? 0x80 : 0) | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }
  if (!masked) return Buffer.concat([header, payload]);
  header[1] |= 0x80;
  const mask = Buffer.from([1, 3, 5, 7]);
  return Buffer.concat([header, mask, Buffer.from(payload.map((byte, index) => byte ^ mask[index % 4]))]);
}

function incomingMessages(socket, consume) {
  let buffer = Buffer.alloc(0);
  let fragments = [];
  socket.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 2) {
      const masked = Boolean(buffer[1] & 0x80);
      let length = buffer[1] & 0x7f;
      let offset = 2;
      if (length === 126) {
        if (buffer.length < 4) return;
        length = buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (buffer.length < 10) return;
        length = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }
      const maskOffset = offset;
      if (masked) offset += 4;
      if (buffer.length < offset + length) return;
      const opcode = buffer[0] & 0xf;
      const fin = Boolean(buffer[0] & 0x80);
      const payload = Buffer.from(buffer.subarray(offset, offset + length));
      if (masked) {
        for (let i = 0; i < length; i += 1) payload[i] ^= buffer[maskOffset + i % 4];
      }
      buffer = buffer.subarray(offset + length);
      if (opcode === 8) {
        socket.end(serverFrame(payload, { opcode: 8 }));
        return;
      }
      if (opcode === 9) {
        socket.write(serverFrame(payload, { opcode: 10 }));
        continue;
      }
      if (opcode > 2) continue;
      fragments.push(payload);
      if (fin) {
        const body = Buffer.concat(fragments);
        fragments = [];
        consume(JSON.parse(body.toString()));
      }
    }
  });
}

export async function responsesFixture(t, handler, options = {}) {
  const { handshake, ...proxyOptions } = options;
  const sockets = new Set();
  const clients = new Set();
  const connections = [];
  const calls = [];
  t.after(() => {
    for (const client of clients) client.destroy();
    for (const socket of sockets) socket.destroy();
  });
  const upstream = await startHttpServer(t, (_req, response) => response.writeHead(400).end());
  upstream.server.on('connection', (socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => socket.destroy());
  });
  upstream.server.on('upgrade', (request, socket) => {
    const token = request.headers.authorization.slice('Bearer '.length);
    const name = JSON.parse(Buffer.from(token.split('.')[1], 'base64url')).token_name;
    const connection = { name, socket, headers: request.headers, index: connections.length };
    connections.push(connection);
    if (handshake?.(connection) === false) return;
    const accept = createHash('sha1').update(`${request.headers['sec-websocket-key']}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    incomingMessages(socket, (event) => {
      calls.push({ name, event, connection: connection.index });
      handler({ ...connection, event, send: (value) => socket.write(serverFrame(value)) });
    });
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, ...proxyOptions });
  const connect = async () => {
    const url = new URL(started.origin);
    const socket = net.connect(Number(url.port), url.hostname);
    clients.add(socket);
    const queue = [];
    let waiter = null;
    const consume = (value) => {
      if (waiter) {
        const pending = waiter;
        waiter = null;
        pending.resolve(value);
      } else queue.push(value);
    };
    socket.on('error', () => waiter?.reject(new Error('client_websocket_error')));
    socket.on('close', () => waiter?.reject(new Error('client_websocket_closed')));
    await new Promise((resolve, reject) => {
      let buffer = Buffer.alloc(0);
      socket.setTimeout(2000, () => reject(new Error('client_handshake_timeout')));
      const onData = (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        const end = buffer.indexOf('\r\n\r\n');
        if (end < 0) return;
        socket.off('data', onData);
        socket.setTimeout(0);
        if (!buffer.toString().startsWith('HTTP/1.1 101 ')) {
          reject(new Error(`client_handshake_rejected: ${buffer.subarray(0, end).toString()}`));
          return;
        }
        incomingMessages(socket, consume);
        const head = buffer.subarray(end + 4);
        if (head.length) socket.emit('data', head);
        resolve();
      };
      socket.on('data', onData);
      socket.once('connect', () => socket.write(`GET /backend-api/codex/responses HTTP/1.1\r\nHost: ${url.host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: c3ludGhldGljLWtleQ==\r\n\r\n`));
    });
    return {
      socket,
      send: (event) => socket.write(serverFrame(event, { masked: true })),
      next: async () => {
        if (queue.length) return queue.shift();
        assert.equal(waiter, null);
        return await new Promise((resolve, reject) => {
          const timer = setTimeout(() => {
            waiter = null;
            reject(new Error('response_event_timeout'));
          }, 2000);
          waiter = {
            resolve: (value) => { clearTimeout(timer); resolve(value); },
            reject: (error) => { clearTimeout(timer); waiter = null; reject(error); },
          };
        });
      },
    };
  };
  return { ...started, connect, calls, connections };
}

export function completed(id, event, output = []) {
  return {
    type: 'response.completed',
    ...(event.stream_id === undefined ? {} : { stream_id: event.stream_id }),
    response: { id, status: 'completed', output },
  };
}

export function usageLimit(event = {}) {
  return {
    type: 'error',
    status: 429,
    ...(event.stream_id === undefined ? {} : { stream_id: event.stream_id }),
    error: { type: 'usage_limit_reached', resets_at: Math.floor(Date.now() / 1000) + 120 },
  };
}
