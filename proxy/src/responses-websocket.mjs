import { WebSocketMessages, webSocketFrame } from './websocket-frames.mjs';

function parsedEvent(message) {
  if (message.opcode !== 1) return null;
  try {
    const value = JSON.parse(message.payload.toString('utf8'));
    return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

function inputItems(input) {
  if (input === undefined || input === null) return [];
  if (typeof input === 'string') return [{ role: 'user', content: input }];
  return Array.isArray(input) ? input : null;
}

function laneOf(event) {
  return typeof event?.stream_id === 'string' ? event.stream_id : '';
}

function recoveryError(event) {
  return {
    type: 'error',
    status: 400,
    ...(event.stream_id === undefined ? {} : { stream_id: event.stream_id }),
    error: {
      type: 'invalid_request_error',
      code: 'previous_response_not_found',
      param: 'previous_response_id',
    },
  };
}

async function writeSocket(socket, bytes) {
  if (socket.destroyed || !socket.writable) throw new Error('websocket_closed');
  if (socket.write(bytes)) return;
  await new Promise((resolve, reject) => {
    const cleanup = () => {
      socket.off('drain', drained);
      socket.off('close', closed);
      socket.off('error', closed);
    };
    const drained = () => { cleanup(); resolve(); };
    const closed = () => { cleanup(); reject(new Error('websocket_closed')); };
    socket.once('drain', drained);
    socket.once('close', closed);
    socket.once('error', closed);
  });
}

class ContextCache {
  constructor(maximumBytes) {
    this.maximumBytes = maximumBytes;
    this.entries = new Map();
    this.bytes = 0;
  }

  get(id) {
    return this.entries.get(id) ?? null;
  }

  save(id, context, peer) {
    const bytes = Buffer.byteLength(JSON.stringify(context));
    if (bytes > this.maximumBytes) return;
    if (this.entries.has(id)) {
      this.bytes -= this.entries.get(id).bytes;
      this.entries.delete(id);
    }
    while (this.bytes + bytes > this.maximumBytes || this.entries.size >= 128) {
      const oldest = this.entries.keys().next().value;
      this.bytes -= this.entries.get(oldest).bytes;
      this.entries.delete(oldest);
    }
    this.entries.set(id, { context, peer, bytes });
    this.bytes += bytes;
  }
}

export function tunnelResponsesWebSocket({
  clientSocket, clientHead, initialPeer, handshake, maximumBytes,
  selectAccount, connectAccount, markUsageLimit, onRetry = () => {},
  onPendingChange = () => {}, onPeerChange = () => {}, onWorkChange = () => {},
}) {
  return new Promise((resolve) => {
    const peers = new Map();
    const allPeers = new Set();
    const connecting = new Map();
    const lanes = new Map();
    const cache = new ContextCache(maximumBytes);
    const operations = new Set();
    let pendingBytes = 0;
    let stopped = false;
    let clientToUpstreamBytes = 0;
    let upstreamToClientBytes = 0;
    let latestPeer = null;

    const stop = () => {
      if (stopped) return;
      stopped = true;
      clientSocket.destroy();
      for (const lane of lanes.values()) {
        if (lane.active) finishRequest(lane.active);
        for (const pending of lane.queue) finishRequest(pending);
        lane.queue = [];
      }
      for (const peer of allPeers) {
        peer.socket.destroy();
        peer.release();
      }
      void (async () => {
        while (operations.size) await Promise.allSettled([...operations]);
        resolve({ clientToUpstreamBytes, upstreamToClientBytes });
      })();
    };

    const run = (work) => {
      let operation;
      operation = Promise.resolve().then(work).catch(stop).finally(() => operations.delete(operation));
      operations.add(operation);
      return operation;
    };

    const sendClient = async (raw) => {
      if (stopped) return;
      await writeSocket(clientSocket, raw);
      upstreamToClientBytes += raw.length;
    };

    const sendPeer = async (peer, raw) => {
      if (stopped) return;
      await writeSocket(peer.socket, raw);
      clientToUpstreamBytes += raw.length;
    };

    const watch = (socket, consume, head, gone, drainBeforeClose = false) => {
      const decoder = new WebSocketMessages(maximumBytes);
      let chain = Promise.resolve();
      const enqueue = (chunk) => {
        socket.pause();
        const previous = chain;
        chain = run(async () => {
          await previous;
          if (stopped) return;
          for (const message of decoder.push(chunk)) {
            if (stopped) return;
            await consume(message);
          }
          if (!stopped) socket.resume();
        });
      };
      socket.on('data', enqueue);
      let closed = false;
      const onClose = () => {
        if (closed) return;
        closed = true;
        if (drainBeforeClose) {
          const pendingRead = chain;
          run(async () => { await pendingRead; gone(); });
        } else gone();
      };
      socket.once('error', onClose);
      socket.once('end', onClose);
      socket.once('close', onClose);
      if (head?.length) enqueue(head);
      else socket.resume();
    };

    const finishRequest = (pending) => {
      if (pending.finished) return;
      pending.finished = true;
      onPendingChange(-1);
      if (pending.countedAccount) onWorkChange(pending.countedAccount, -1);
      pending.peer?.pending.delete(pending.lane);
      pendingBytes -= pending.bytes;
      const lane = lanes.get(pending.lane);
      if (lane?.active !== pending) return;
      lane.active = null;
      if (!stopped && lane.queue.length) {
        lane.active = lane.queue.shift();
        run(() => dispatch(lane.active));
      }
    };

    const remember = (pending, event) => {
      if (!pending.context || typeof event.response?.id !== 'string') return;
      let output = event.response.output;
      if (!Array.isArray(output) || (output.length === 0 && pending.output.size)) {
        output = [...pending.output].sort(([left], [right]) => left - right).map(([, item]) => item);
      }
      if (!Array.isArray(output)) return;
      cache.save(event.response.id, [...pending.context, ...output], pending.peer);
    };

    const peerForEvent = (peer, event) => {
      const exact = peer.pending.get(laneOf(event));
      if (exact) return exact;
      const id = event.response_id ?? event.response?.id;
      if (id) {
        for (const pending of peer.pending.values()) if (pending.responseId === id) return pending;
      }
      if (event.type === 'error' && event.stream_id === undefined && peer.pending.size === 1) {
        return peer.pending.values().next().value;
      }
      return null;
    };

    const receivePeer = async (peer, message) => {
      if (message.opcode === 9) return await sendPeer(peer, webSocketFrame(message.payload, { opcode: 10, masked: true }));
      if (message.opcode === 10) return;
      if (message.opcode === 8) {
        peer.socket.end(webSocketFrame(message.payload, { opcode: 8, masked: true }));
        if (peer.pending.size) stop();
        return;
      }
      const event = parsedEvent(message);
      if (!event) {
        for (const pending of peer.pending.values()) pending.started = true;
        return await sendClient(message.raw);
      }
      const pending = peerForEvent(peer, event);
      if (!pending && peer.retiredLanes.has(laneOf(event))
          && (event.type === 'error' || event.type?.startsWith('response.'))) return;
      if (event.type === 'error' && await markUsageLimit(peer.name, event)) {
        if (pending && !pending.started && !pending.interrupted) {
          const next = await selectAccount(pending.attempted);
          if (next && !stopped) {
            peer.pending.delete(pending.lane);
            peer.retiredLanes.add(pending.lane);
            if (await dispatch(pending, next)) {
              onRetry(peer.name, pending.peer.name, pending.attempted.size);
              return;
            }
          }
        }
      }
      if (pending) {
        pending.started = true;
        if (typeof event.response?.id === 'string') pending.responseId = event.response.id;
        if (event.type === 'response.output_item.done' && event.item) {
          const index = Number.isSafeInteger(event.output_index) ? event.output_index : pending.output.size;
          pending.output.set(index, event.item);
        }
        if (event.type === 'response.completed') remember(pending, event);
      }
      await sendClient(message.raw);
      if (pending && ['error', 'response.completed', 'response.failed', 'response.incomplete'].includes(event.type)) {
        finishRequest(pending);
      }
    };

    const attachPeer = (connected) => {
      const peer = { ...connected, pending: new Map(), retiredLanes: new Set(), closed: false };
      const release = connected.release;
      onPeerChange(peer.name, 1);
      let released = false;
      peer.release = () => {
        if (released) return;
        released = true;
        onPeerChange(peer.name, -1);
        release();
      };
      if (stopped) {
        peer.socket.destroy();
        peer.release();
        return peer;
      }
      peers.set(peer.name, peer);
      allPeers.add(peer);
      const gone = () => {
        peer.closed = true;
        peer.release();
        allPeers.delete(peer);
        if (!stopped && peer.pending.size) stop();
      };
      watch(peer.socket, (message) => receivePeer(peer, message), peer.head, gone, true);
      return peer;
    };

    const getPeer = async (name, attempted) => {
      const existing = peers.get(name);
      if (existing && !existing.closed && !existing.socket.destroyed) return existing;
      if (connecting.has(name)) return await connecting.get(name);
      const connection = connectAccount(name, attempted).then((connected) => connected ? attachPeer(connected) : null);
      connecting.set(name, connection);
      try {
        return await connection;
      } finally {
        connecting.delete(name);
      }
    };

    const dispatch = async (pending, requestedName = null) => {
      if (stopped) return false;
      const name = requestedName ?? await selectAccount(pending.attempted);
      if (!name) {
        if (requestedName) return false;
        await sendClient(webSocketFrame({
          type: 'error', status: 503,
          ...(pending.event.stream_id === undefined ? {} : { stream_id: pending.event.stream_id }),
          error: { type: 'proxy_no_eligible_account' },
        }));
        finishRequest(pending);
        return true;
      }
      pending.attempted.add(name);
      const peer = await getPeer(name, pending.attempted);
      if (!peer || stopped) return false;
      pending.attempted.add(peer.name);
      let event = pending.event;
      const previous = event.previous_response_id ? cache.get(event.previous_response_id) : null;
      const input = inputItems(event.input);
      if (pending.context === undefined) {
        pending.context = input === null || (event.previous_response_id && !previous)
          ? null : [...(previous?.context ?? []), ...input];
      }
      const changingContextOwner = event.previous_response_id
        && ((previous && previous.peer !== peer) || (!previous && pending.peer && pending.peer !== peer));
      if (changingContextOwner) {
        if (!pending.context) {
          await sendClient(webSocketFrame(recoveryError(event)));
          finishRequest(pending);
          return true;
        }
        event = { ...event, previous_response_id: null, input: pending.context };
        if (Buffer.byteLength(JSON.stringify(event)) > maximumBytes) {
          await sendClient(webSocketFrame(recoveryError(pending.event)));
          finishRequest(pending);
          return true;
        }
      }
      if (pending.countedAccount) onWorkChange(pending.countedAccount, -1);
      pending.countedAccount = peer.name;
      onWorkChange(peer.name, 1);
      pending.peer = peer;
      peer.retiredLanes.delete(pending.lane);
      peer.pending.set(pending.lane, pending);
      lanes.get(pending.lane).lastPeer = peer;
      latestPeer = peer;
      await sendPeer(peer, event === pending.event ? pending.raw : webSocketFrame(event, { masked: true }));
      return true;
    };

    const receiveClient = async (message) => {
      if (message.opcode === 9) return await sendClient(webSocketFrame(message.payload, { opcode: 10 }));
      if (message.opcode === 10) return;
      if (message.opcode === 8) {
        clientSocket.end(webSocketFrame(message.payload, { opcode: 8 }));
        stop();
        return;
      }
      const event = parsedEvent(message);
      if (event?.type === 'response.create') {
        const key = laneOf(event);
        if (!lanes.has(key)) lanes.set(key, { active: null, queue: [], lastPeer: latestPeer });
        const lane = lanes.get(key);
        const pending = {
          lane: key, event, raw: message.raw, bytes: message.raw.length,
          peer: lane.lastPeer, attempted: new Set(), started: false,
          interrupted: false, finished: false, output: new Map(),
        };
        if (pendingBytes + pending.bytes > maximumBytes) throw new Error('websocket_pending_input_too_large');
        pendingBytes += pending.bytes;
        onPendingChange(1);
        if (lane.active) lane.queue.push(pending);
        else {
          lane.active = pending;
          if (!await dispatch(pending)) throw new Error('websocket_account_unavailable');
        }
        return;
      }
      let pending = event ? lanes.get(laneOf(event))?.active : null;
      if (event?.response_id) {
        pending = [...lanes.values()].map((lane) => lane.active)
          .find((candidate) => candidate?.responseId === event.response_id) ?? pending;
      }
      const target = pending?.peer ?? latestPeer;
      for (const active of target?.pending.values() ?? []) {
        if (pending && pending !== active) continue;
        active.interrupted = true;
        active.context = null;
      }
      if (target) await sendPeer(target, message.raw);
    };

    latestPeer = attachPeer(initialPeer);
    clientSocket.write(handshake);
    watch(clientSocket, receiveClient, clientHead, stop);
  });
}
