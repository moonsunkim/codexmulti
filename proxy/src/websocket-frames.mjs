import { randomBytes } from 'node:crypto';

class ByteQueue {
  constructor() {
    this.chunks = [];
    this.offset = 0;
    this.length = 0;
  }

  push(chunk) {
    if (!chunk.length) return;
    this.chunks.push(chunk);
    this.length += chunk.length;
  }

  peek(length) {
    if (this.chunks[0].length - this.offset >= length) {
      return this.chunks[0].subarray(this.offset, this.offset + length);
    }
    const result = Buffer.allocUnsafe(length);
    let written = 0;
    for (let index = 0; written < length; index += 1) {
      const chunk = this.chunks[index];
      const start = index === 0 ? this.offset : 0;
      const count = Math.min(length - written, chunk.length - start);
      chunk.copy(result, written, start, start + count);
      written += count;
    }
    return result;
  }

  take(length) {
    const result = this.peek(length);
    let remaining = length;
    while (remaining) {
      const count = Math.min(remaining, this.chunks[0].length - this.offset);
      this.offset += count;
      remaining -= count;
      if (this.offset === this.chunks[0].length) {
        this.chunks.shift();
        this.offset = 0;
      }
    }
    this.length -= length;
    return result;
  }
}

export class WebSocketMessages {
  constructor(maximumBytes) {
    this.maximumBytes = maximumBytes;
    this.bytes = new ByteQueue();
    this.fragments = [];
    this.payloads = [];
    this.messageBytes = 0;
    this.opcode = null;
  }

  push(chunk) {
    this.bytes.push(chunk);
    const messages = [];
    while (this.bytes.length >= 2) {
      let header = this.bytes.peek(Math.min(this.bytes.length, 14));
      const fin = Boolean(header[0] & 0x80);
      const opcode = header[0] & 0x0f;
      const masked = Boolean(header[1] & 0x80);
      let length = header[1] & 0x7f;
      let offset = 2;
      if (header[0] & 0x70) throw new Error('websocket_extensions_not_negotiated');
      if (length === 126) {
        if (header.length < 4) break;
        length = header.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (header.length < 10) break;
        const wide = header.readBigUInt64BE(2);
        if (wide > BigInt(this.maximumBytes)) throw new Error('websocket_message_too_large');
        length = Number(wide);
        offset = 10;
      }
      const control = opcode >= 8;
      if (length > this.maximumBytes || (!control && this.messageBytes + length > this.maximumBytes)) {
        throw new Error('websocket_message_too_large');
      }
      if (control && (!fin || length > 125 || ![8, 9, 10].includes(opcode))) {
        throw new Error('invalid_websocket_control_frame');
      }
      const maskOffset = offset;
      if (masked) offset += 4;
      if (this.bytes.length < offset + length) break;
      const raw = this.bytes.take(offset + length);
      header = raw;
      const payload = Buffer.from(raw.subarray(offset));
      if (masked) {
        for (let index = 0; index < length; index += 1) payload[index] ^= header[maskOffset + index % 4];
      }
      if (control) {
        messages.push({ opcode, raw, payload });
        continue;
      }
      if (opcode === 1 || opcode === 2) {
        if (this.opcode !== null) throw new Error('interleaved_websocket_fragments');
        this.opcode = opcode;
      } else if (opcode !== 0 || this.opcode === null) {
        throw new Error('invalid_websocket_data_frame');
      }
      this.fragments.push(raw);
      this.payloads.push(payload);
      this.messageBytes += length;
      if (!fin) continue;
      const message = {
        opcode: this.opcode,
        raw: this.fragments.length === 1 ? raw : Buffer.concat(this.fragments),
        payload: this.payloads.length === 1 ? payload : Buffer.concat(this.payloads, this.messageBytes),
      };
      messages.push(message);
      this.fragments = [];
      this.payloads = [];
      this.messageBytes = 0;
      this.opcode = null;
    }
    return messages;
  }
}

export function webSocketFrame(value, { masked = false, opcode = 1 } = {}) {
  const payload = Buffer.isBuffer(value) ? value : Buffer.from(JSON.stringify(value));
  const extended = payload.length < 126 ? 0 : payload.length <= 65535 ? 2 : 8;
  const offset = 2 + extended + (masked ? 4 : 0);
  const result = Buffer.allocUnsafe(offset + payload.length);
  result[0] = 0x80 | opcode;
  result[1] = (masked ? 0x80 : 0) | (extended === 0 ? payload.length : extended === 2 ? 126 : 127);
  if (extended === 2) result.writeUInt16BE(payload.length, 2);
  if (extended === 8) result.writeBigUInt64BE(BigInt(payload.length), 2);
  payload.copy(result, offset);
  if (masked) {
    const mask = randomBytes(4);
    mask.copy(result, 2 + extended);
    for (let index = 0; index < payload.length; index += 1) result[offset + index] ^= mask[index % 4];
  }
  return result;
}
