import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { chmod, mkdir, rm, writeFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { zstdDecompressSync } from 'node:zlib';
import {
  SCRATCH_ROOT,
  request,
  sseOk,
  startHttpServer,
  startTestProxy,
  syntheticAuth,
} from './helpers.mjs';

const codexProbe = new Promise((resolve) => {
  execFile('codex', ['--version'], (error, stdout, stderr) => {
    if (error) {
      const detail = error.code === 'ENOENT' ? 'executable not found on PATH' : String(stderr || error.message).trim();
      resolve({ available: false, reason: detail });
      return;
    }
    resolve({ available: true });
  });
});

async function requireCodex(testContext) {
  const probe = await codexProbe;
  if (probe.available) return true;
  testContext.skip(`Codex CLI unavailable: ${probe.reason}`);
  return false;
}

test('smoke runtime uses Node 22.15+', () => {
  const [major, minor] = process.versions.node.split('.').map(Number);
  assert.equal(major > 22 || (major === 22 && minor >= 15), true);
});

async function readIncoming(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

function selectedName(req) {
  const token = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
  try {
    return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()).token_name;
  } catch {
    return null;
  }
}

async function prepareCodexHome(root) {
  const home = path.join(root, 'codex-home');
  const work = path.join(root, 'work');
  await mkdir(home, { recursive: true, mode: 0o700 });
  await mkdir(work, { recursive: true, mode: 0o700 });
  await chmod(home, 0o700);
  const auth = syntheticAuth('codex-client', 4_102_444_800);
  await writeFile(path.join(home, 'auth.json'), `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
  await chmod(path.join(home, 'auth.json'), 0o600);
  return { home, work };
}

async function runCodex(testContext, { home, work, proxyOrigin, prompt = 'reply with the single word ok', extraConfig = [] }) {
  const args = [
    'exec',
    '--ignore-user-config',
    '-c', `chatgpt_base_url="${proxyOrigin}/backend-api/"`,
    '-c', `openai_base_url="${proxyOrigin}/backend-api/codex"`,
    '-c', 'service_tier="priority"',
    '-c', 'model="gpt-5.6-sol"',
    '--skip-git-repo-check',
    '-C', work,
    prompt,
  ];
  const promptValue = args.pop();
  for (const value of extraConfig) args.push('-c', value);
  args.push(promptValue);
  return await new Promise((resolve, reject) => {
    const child = spawn('codex', args, {
      env: { ...process.env, CODEX_HOME: home },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    testContext.after(() => {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.once('error', reject);
    const timer = setTimeout(() => child.kill('SIGTERM'), 30_000);
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      resolve({
        code,
        signal,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8'),
        args,
      });
    });
  });
}

async function runAppServerTurns(testContext, {
  home, work, proxyOrigin, turnCount = 2, prompt = 'reply with the single word ok', beforeStop = async () => {},
  extraConfig = [],
}) {
  const args = [
    'app-server', '--listen', 'stdio://',
    '-c', `chatgpt_base_url="${proxyOrigin}/backend-api/"`,
    '-c', `openai_base_url="${proxyOrigin}/backend-api/codex"`,
    '-c', 'service_tier="priority"',
    '-c', 'model="gpt-5.6-sol"',
  ];
  for (const value of extraConfig) args.push('-c', value);
  const child = spawn('codex', args, {
    env: { ...process.env, CODEX_HOME: home },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  testContext.after(() => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
  });
  let stderr = '';
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const messages = [];
  const waiters = [];
  const lines = createInterface({ input: child.stdout });
  lines.on('line', (line) => {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }
    messages.push(message);
    for (const waiter of [...waiters]) {
      if (waiter.predicate(message)) {
        waiters.splice(waiters.indexOf(waiter), 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      }
    }
  });
  const waitFor = (predicate, label) => {
    const existing = messages.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, timer: null };
      waiter.timer = setTimeout(() => {
        const index = waiters.indexOf(waiter);
        if (index !== -1) waiters.splice(index, 1);
        reject(new Error(`app_server_timeout:${label}:${stderr}:${JSON.stringify(messages.slice(-10))}`));
      }, 20_000);
      waiters.push(waiter);
    });
  };
  const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
  send({ id: 1, method: 'initialize', params: {
    clientInfo: { name: 'codex-failover-smoke', version: '1.0.0' },
    capabilities: { experimentalApi: true },
  } });
  await waitFor((message) => message.id === 1 && message.result, 'initialize');
  send({ method: 'initialized' });
  send({ id: 2, method: 'thread/start', params: {
    model: 'gpt-5.6-sol', serviceTier: 'priority', cwd: work,
    approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true,
  } });
  const threadStarted = await waitFor((message) => message.id === 2 && message.result?.thread?.id, 'thread_start');
  const threadId = threadStarted.result.thread.id;
  for (let offset = 0; offset < turnCount; offset += 1) {
    const id = 3 + offset;
    send({ id, method: 'turn/start', params: {
      threadId,
      input: [{ type: 'text', text: prompt, textElements: [] }],
    } });
    await waitFor((message) => message.id === id && message.result?.turn?.id, `turn_response_${id}`);
    const completed = await waitFor((message) => message.method === 'turn/completed'
      && message.params?.turn?.status !== 'inProgress'
      && message.params?.turn?.id === messages.find((candidate) => candidate.id === id)?.result?.turn?.id,
    `turn_completed_${id}`);
    assert.equal(completed.params.turn.status, 'completed', JSON.stringify(completed));
  }
  await beforeStop();
  child.kill('SIGTERM');
  await new Promise((resolve) => child.once('exit', resolve));
  lines.close();
  return { messages, stderr, args };
}

async function setupSmoke(testContext, mode) {
  await mkdir(SCRATCH_ROOT, { recursive: true });
  const root = path.join(SCRATCH_ROOT, `codex-failover-smoke-${randomUUID()}`);
  await mkdir(root, { recursive: true, mode: 0o700 });
  await chmod(root, 0o700);
  testContext.after(async () => rm(root, { recursive: true, force: true }));
  const captures = [];
  const internal = {
    attemptAccounts: [],
    bodyHashes: [],
    upgradeThreads: [],
    postThreads: [],
    upgradeSubagents: [],
    postSubagents: [],
    childPostSeen: false,
    parentWaitCalls: 0,
  };
  const upstream = await startHttpServer(testContext, async (req, res) => {
    const raw = await readIncoming(req);
    if (req.url.split('?')[0] === '/backend-api/codex/responses' && req.method === 'POST') {
      let bodyKeys = [];
      let bodyText = '';
      try {
        const decoded = req.headers['content-encoding'] === 'zstd' ? zstdDecompressSync(raw) : raw;
        bodyText = decoded.toString('utf8');
        const parsedBody = JSON.parse(bodyText);
        bodyKeys = Object.keys(parsedBody).sort();
      } catch {
        bodyKeys = ['<unavailable>'];
      }
      const account = selectedName(req);
      internal.attemptAccounts.push(account);
      internal.bodyHashes.push(createHash('sha256').update(raw).digest('hex'));
      internal.postThreads.push(req.headers['thread-id']
        ? createHash('sha256').update(req.headers['thread-id']).digest('hex').slice(0, 12) : null);
      internal.postSubagents.push(req.headers['x-openai-subagent'] ?? null);
      captures.push({
        kind: 'http', method: req.method, path: req.url.split('?')[0],
        body_keys: bodyKeys,
        headers: {
          authorization: '<redacted>',
          'chatgpt-account-id': '<redacted>',
          'content-encoding': req.headers['content-encoding'] ?? null,
          'session-id': req.headers['session-id'] ? '<synthetic-id>' : null,
          'thread-id': req.headers['thread-id'] ? '<synthetic-id>' : null,
        },
      });
      if (mode === 'failover' && account === 'a') {
        const body = Buffer.from(JSON.stringify({
          error: { type: 'usage_limit_reached', resets_at: Math.floor(Date.now() / 1000) + 600 },
        }));
        res.writeHead(429, { 'content-type': 'application/json', 'content-length': String(body.length) });
        res.end(body);
        return;
      }
      if (mode === 'multi-agent') {
        let events;
        if (req.headers['x-openai-subagent']) {
          internal.childPostSeen = true;
          events = [
            { type: 'response.created', response: { id: 'smoke-child' } },
            {
              type: 'response.output_item.done',
              item: {
                type: 'message', role: 'assistant', id: 'smoke-child-message',
                content: [{ type: 'output_text', text: 'child ok' }],
              },
            },
            { type: 'response.completed', response: { id: 'smoke-child', usage: {
              input_tokens: 0, input_tokens_details: null, output_tokens: 0,
              output_tokens_details: null, total_tokens: 0,
            } } },
          ];
        } else if (bodyText.includes('spawn-child-call') && internal.childPostSeen) {
          events = [
            { type: 'response.created', response: { id: 'smoke-parent-complete' } },
            {
              type: 'response.output_item.done',
              item: {
                type: 'message', role: 'assistant', id: 'smoke-parent-message',
                content: [{ type: 'output_text', text: 'parent ok' }],
              },
            },
            { type: 'response.completed', response: { id: 'smoke-parent-complete', usage: {
              input_tokens: 0, input_tokens_details: null, output_tokens: 0,
              output_tokens_details: null, total_tokens: 0,
            } } },
          ];
        } else if (bodyText.includes('spawn-child-call')) {
          internal.parentWaitCalls += 1;
          events = [
            { type: 'response.created', response: { id: `smoke-parent-wait-${internal.parentWaitCalls}` } },
            {
              type: 'response.output_item.done',
              item: {
                type: 'function_call', call_id: `wait-child-call-${internal.parentWaitCalls}`,
                namespace: 'collaboration', name: 'wait_agent',
                arguments: JSON.stringify({ timeout_ms: 10_000 }),
              },
            },
            { type: 'response.completed', response: { id: `smoke-parent-wait-${internal.parentWaitCalls}`, usage: {
              input_tokens: 0, input_tokens_details: null, output_tokens: 0,
              output_tokens_details: null, total_tokens: 0,
            } } },
          ];
        } else {
          events = [
            { type: 'response.created', response: { id: 'smoke-parent-spawn' } },
            {
              type: 'response.output_item.done',
              item: {
                type: 'function_call', call_id: 'spawn-child-call', namespace: 'collaboration',
                name: 'spawn_agent', arguments: JSON.stringify({
                  message: 'child synthetic task', task_name: 'synthetic_child',
                }),
              },
            },
            { type: 'response.completed', response: { id: 'smoke-parent-spawn', usage: {
              input_tokens: 0, input_tokens_details: null, output_tokens: 0,
              output_tokens_details: null, total_tokens: 0,
            } } },
          ];
        }
        const stream = events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join('');
        res.writeHead(200, { 'content-type': 'text/event-stream', 'x-request-id': 'synthetic-smoke' });
        res.end(stream);
        return;
      }
      res.writeHead(200, { 'content-type': 'text/event-stream', 'x-request-id': 'synthetic-smoke' });
      res.end(sseOk(`smoke-${mode}`));
      return;
    }
    res.writeHead(400, { 'content-type': 'application/json' });
    res.end('{}');
  });
  upstream.server.on('upgrade', (_req, socket) => {
    socket.end('HTTP/1.1 426 Upgrade Required\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  });
  const started = await startTestProxy(testContext, {
    temp: path.join(root, 'proxy'),
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b', 'c'],
  });
  started.proxy.server.on('upgrade', (req) => {
    internal.upgradeThreads.push(req.headers['thread-id']
      ? createHash('sha256').update(req.headers['thread-id']).digest('hex').slice(0, 12) : null);
    internal.upgradeSubagents.push(req.headers['x-openai-subagent'] ?? null);
    captures.push({
      kind: 'upgrade', method: req.method, path: req.url.split('?')[0],
      headers: {
        authorization: '<redacted>',
        'chatgpt-account-id': '<redacted>',
        upgrade: req.headers.upgrade,
      },
    });
  });
  return { ...started, captures, internal, root };
}

test('Codex CLI smoke: upstream 426 falls back to HTTP/SSE and prints ok', { timeout: 45_000 }, async (t) => {
  if (!await requireCodex(t)) return;
  const setup = await setupSmoke(t, 'normal');
  const codex = await prepareCodexHome(setup.root);
  const result = await runCodex(t, { ...codex, proxyOrigin: setup.origin });
  assert.equal(result.signal, null, result.stderr);
  assert.equal(result.code, 0, result.stderr);
  assert.match(`${result.stdout}\n${result.stderr}`, /\bok\b/i);
  const responseCaptures = setup.captures.filter(({ path: requestPath }) => requestPath === '/backend-api/codex/responses');
  assert.deepEqual(responseCaptures.map(({ kind }) => kind), ['upgrade', 'http']);
  assert.deepEqual(responseCaptures[1].body_keys.includes('input'), true);
  assert.doesNotMatch(JSON.stringify(responseCaptures), /synthetic-signature|synthetic-refresh|Bearer\s+eyJ/);
});

test('Codex CLI smoke: account A 429 fails over to B and status reports cooldown', { timeout: 45_000 }, async (t) => {
  if (!await requireCodex(t)) return;
  const setup = await setupSmoke(t, 'failover');
  const codex = await prepareCodexHome(setup.root);
  const result = await runCodex(t, { ...codex, proxyOrigin: setup.origin });
  assert.equal(result.signal, null, result.stderr);
  assert.equal(result.code, 0, result.stderr);
  assert.match(`${result.stdout}\n${result.stderr}`, /\bok\b/i);
  const responseCaptures = setup.captures.filter(({ kind, path: requestPath }) => kind === 'http'
    && requestPath === '/backend-api/codex/responses');
  assert.deepEqual(setup.internal.attemptAccounts, ['a', 'b']);
  assert.deepEqual(responseCaptures[0].body_keys, responseCaptures[1].body_keys);
  assert.equal(setup.internal.bodyHashes[0], setup.internal.bodyHashes[1]);
  const status = JSON.parse((await request(setup.origin, '/_proxy/status')).body);
  assert.equal(status.active, 'b');
  assert.equal(status.accounts.find(({ name }) => name === 'a').state, 'COOLDOWN');
  assert.doesNotMatch(JSON.stringify(status), /synthetic-signature|synthetic-refresh|synthetic-account/);
});

test('Codex CLI app-server smoke: upstream 426 fallback stays sticky across two turns', { timeout: 60_000 }, async (t) => {
  if (!await requireCodex(t)) return;
  const setup = await setupSmoke(t, 'normal');
  const codex = await prepareCodexHome(setup.root);
  const result = await runAppServerTurns(t, { ...codex, proxyOrigin: setup.origin });
  const responseCaptures = setup.captures.filter(({ path: requestPath }) => requestPath === '/backend-api/codex/responses');
  assert.deepEqual(responseCaptures.map(({ kind }) => kind), ['upgrade', 'http', 'http']);
  assert.match(JSON.stringify(result.messages), /\bok\b/i);
  assert.doesNotMatch(JSON.stringify(responseCaptures), /synthetic-signature|synthetic-refresh|Bearer\s+eyJ/);
});

test('Codex CLI smoke: parent and spawned child each relay one Upgrade before upstream 426', { timeout: 60_000 }, async (t) => {
  if (!await requireCodex(t)) return;
  const setup = await setupSmoke(t, 'multi-agent');
  const codex = await prepareCodexHome(setup.root);
  const result = await runCodex(t, {
    ...codex,
    proxyOrigin: setup.origin,
    prompt: 'spawn a synthetic child',
    extraConfig: ['features.multi_agent_v2=true'],
  });
  assert.equal(result.signal, null, result.stderr);
  assert.equal(result.code, 0, result.stderr);
  const responseCaptures = setup.captures.filter(({ path: requestPath }) => requestPath === '/backend-api/codex/responses');
  const upgrades = responseCaptures.filter(({ kind }) => kind === 'upgrade');
  assert.equal(upgrades.length, 2);
  assert.equal(setup.internal.upgradeSubagents.filter((value) => value === null).length, 1);
  assert.equal(setup.internal.upgradeSubagents.filter((value) => value === 'collab_spawn').length, 1);
  assert.ok(setup.internal.postSubagents.includes(null));
  assert.ok(setup.internal.postSubagents.includes('collab_spawn'));
  assert.equal(new Set(setup.internal.upgradeThreads).size, 2,
    JSON.stringify({ upgrades: setup.internal.upgradeSubagents, posts: setup.internal.postSubagents }));
  for (const thread of setup.internal.upgradeThreads) {
    assert.ok(setup.internal.postThreads.includes(thread));
  }
  const rootThread = setup.internal.upgradeThreads[setup.internal.upgradeSubagents.indexOf(null)];
  const childThread = setup.internal.upgradeThreads[setup.internal.upgradeSubagents.indexOf('collab_spawn')];
  assert.ok(setup.internal.postThreads.filter((value) => value === rootThread).length >= 2);
  assert.equal(setup.internal.postThreads.filter((value) => value === childThread).length, 1);
  assert.match(`${result.stdout}\n${result.stderr}`, /parent ok|child ok/);
});
