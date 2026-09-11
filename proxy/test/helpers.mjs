import http from 'node:http';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { chmod, mkdir, rm, writeFile } from 'node:fs/promises';
import { createProxy } from '../src/server.mjs';

export const SCRATCH_ROOT = '/private/tmp/codexmulti-proxy-tests';

export function jwt(payload) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.synthetic-signature`;
}

export function syntheticAuth(name, exp, overrides = {}) {
  const claims = {
    'https://api.openai.com/auth': {
      chatgpt_plan_type: 'pro',
      chatgpt_user_id: `synthetic-user-${name}`,
      chatgpt_account_id: `synthetic-account-${name}`,
      chatgpt_account_is_fedramp: false,
    },
  };
  const { tokens: tokenOverrides = {}, ...topLevelOverrides } = overrides;
  return {
    auth_mode: 'chatgpt',
    OPENAI_API_KEY: null,
    fixture_marker: { preserve: true },
    tokens: {
      id_token: jwt(claims),
      access_token: jwt({ ...claims, exp, token_name: name }),
      refresh_token: `synthetic-refresh-${name}`,
      account_id: `synthetic-account-${name}`,
      ...tokenOverrides,
    },
    last_refresh: new Date(0).toISOString(),
    ...topLevelOverrides,
  };
}

export async function makeTempDir(testContext) {
  await mkdir(SCRATCH_ROOT, { recursive: true, mode: 0o700 });
  const directory = path.join(SCRATCH_ROOT, `codex-failover-test-${randomUUID()}`);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
  testContext.after(async () => rm(directory, { recursive: true, force: true }));
  return directory;
}

export async function writeAccountAuth(root, name, auth) {
  const directory = path.join(root, name);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
  const file = path.join(directory, 'auth.json');
  await writeFile(file, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
  await chmod(file, 0o600);
  return file;
}

export async function startHttpServer(testContext, handler) {
  const server = http.createServer(handler);
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  testContext.after(async () => {
    if (!server.listening) return;
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(() => resolve())).catch(() => {});
  });
  const port = server.address().port;
  return { server, port, origin: `http://127.0.0.1:${port}` };
}

export function sseOk(id = 'synthetic-response', text = 'ok') {
  const events = [
    { type: 'response.created', response: { id } },
    {
      type: 'response.output_item.done',
      item: {
        type: 'message', role: 'assistant', id: `${id}-message`,
        content: [{ type: 'output_text', text }],
      },
    },
    {
      type: 'response.completed',
      response: {
        id,
        usage: {
          input_tokens: 0, input_tokens_details: null, output_tokens: 0,
          output_tokens_details: null, total_tokens: 0,
        },
      },
    },
  ];
  return events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join('');
}

export async function request(origin, requestPath, options = {}) {
  const body = options.body === undefined ? null
    : Buffer.isBuffer(options.body) ? options.body : Buffer.from(options.body);
  return await new Promise((resolve, reject) => {
    const req = http.request(`${origin}${requestPath}`, {
      method: options.method ?? 'GET',
      headers: {
        ...(body ? { 'content-length': String(body.length) } : {}),
        ...options.headers,
      },
    }, async (res) => {
      const chunks = [];
      try {
        for await (const chunk of res) chunks.push(chunk);
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body: Buffer.concat(chunks),
        });
      } catch (error) {
        reject(error);
      }
    });
    req.once('error', reject);
    req.end(body);
  });
}

export async function startTestProxy(testContext, {
  temp,
  upstreamOrigin,
  accountNames = ['a', 'b', 'c'],
  labelsByName = {},
  authByName = {},
  now = Date.now(),
  config = {},
  options = {},
} = {}) {
  const root = temp ?? await makeTempDir(testContext);
  const exp = Math.floor(now / 1000) + 3600;
  const accounts = [];
  for (const name of accountNames) {
    accounts.push({
      name,
      ...(labelsByName[name] === undefined ? {} : { label: labelsByName[name] }),
      auth_file: await writeAccountAuth(root, name, authByName[name] ?? syntheticAuth(name, exp)),
    });
  }
  const proxyConfig = {
    listen_host: '127.0.0.1',
    port: 0,
    mode: 'failover',
    accounts,
    upstream_chatgpt_base_url: `${upstreamOrigin}/backend-api/`,
    upstream_openai_base_url: `${upstreamOrigin}/backend-api/codex`,
    request_body_limit_bytes: 64 * 1024 * 1024,
    token_refresh_skew_seconds: 300,
    default_cooldown_seconds: 1800,
    cooldown_safety_margin_seconds: 60,
    allow_insecure_upstream: true,
    state_file: path.join(root, 'state/state.json'),
    log_file: null,
    ...config,
  };
  const configPath = path.join(root, 'config.json');
  await writeFile(configPath, `${JSON.stringify(proxyConfig, null, 2)}\n`, { mode: 0o600 });
  const proxy = await createProxy(proxyConfig, {
    now: () => now,
    configPath,
    ...options,
  });
  const address = await proxy.listen();
  testContext.after(async () => {
    if (proxy.server.listening) await proxy.close();
  });
  return { proxy, origin: `http://127.0.0.1:${address.port}`, root, accounts, configPath };
}
