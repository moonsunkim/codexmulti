import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { appendFileSync, existsSync, renameSync, statSync } from 'node:fs';
import { chmod, mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import {
  AccountRegistry,
  ACCOUNT_NAME_RE,
  DEFAULT_REFRESH_SKEW_SECONDS,
  Mutex,
  assertSafeAuthPath,
  expandHome,
} from './accounts.mjs';
import { AccountState, FailoverManager } from './failover.mjs';
import {
  bufferForClassification,
  buildUpstreamHeaders,
  classify429,
  createUpstreamAgents,
  discardResponse,
  openUpstream,
  sendBuffered,
  streamResponse,
} from './upstream.mjs';

export const CONFIG_DEFAULTS = Object.freeze({
  listen_host: '127.0.0.1',
  port: 8787,
  mode: 'failover',
  upstream_chatgpt_base_url: 'https://chatgpt.com/backend-api/',
  upstream_openai_base_url: 'https://chatgpt.com/backend-api/codex',
  request_body_limit_bytes: 64 * 1024 * 1024,
  token_refresh_skew_seconds: DEFAULT_REFRESH_SKEW_SECONDS,
  default_cooldown_seconds: 1800,
  cooldown_safety_margin_seconds: 60,
  allow_insecure_upstream: false,
});

const LOG_FIELDS = new Set([
  'timestamp', 'level', 'event', 'request_id', 'method', 'route', 'status',
  'duration_ms', 'account_name', 'attempt', 'cooldown_until', 'error_code',
  'error_message', 'relayed_bytes', 'upstream_status', 'terminal_seen',
  'added', 'removed', 'renamed', 'migrated',
]);

export function redactSecret(value) {
  if (typeof value === 'string') {
    return value
      .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer <redacted>')
      .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '<redacted>')
      .replace(/\b(?:rt|refresh)[-_][A-Za-z0-9._~+/=-]+\b/gi, '<redacted>');
  }
  if (Array.isArray(value)) return value.map(redactSecret);
  if (value && typeof value === 'object') {
    const output = {};
    for (const [key, nested] of Object.entries(value)) {
      if (/(authorization|cookie|token|account(?!_name)|attestation|secret)/i.test(key)) {
        output[key] = '<redacted>';
      } else {
        output[key] = redactSecret(nested);
      }
    }
    return output;
  }
  return value;
}

export function createLogger(logFile, options = {}) {
  if (!logFile) return () => {};
  const maximumBytes = options.maximumBytes ?? 5 * 1024 * 1024;
  const backups = options.backups ?? 3;
  return (event) => {
    const safe = redactSecret(event);
    const filtered = {};
    for (const key of LOG_FIELDS) {
      if (safe[key] !== undefined) filtered[key] = safe[key];
    }
    if (existsSync(logFile) && statSync(logFile).size >= maximumBytes) {
      for (let index = backups - 1; index >= 1; index -= 1) {
        const source = `${logFile}.${index}`;
        if (existsSync(source)) renameSync(source, `${logFile}.${index + 1}`);
      }
      renameSync(logFile, `${logFile}.1`);
    }
    appendFileSync(logFile, `${JSON.stringify(filtered)}\n`, { mode: 0o600 });
  };
}

function positiveInteger(value, name, { allowZero = false } = {}) {
  if (!Number.isSafeInteger(value) || value < (allowZero ? 0 : 1)) throw new Error(`invalid_${name}`);
  return value;
}

function validateUpstream(value, expected, allowInsecure) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error('invalid_upstream_url');
  }
  if (url.username || url.password || url.hash) throw new Error('invalid_upstream_url');
  if (!allowInsecure) {
    if (url.href !== new URL(expected).href) throw new Error('invalid_upstream_url');
  } else if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1') {
    throw new Error('invalid_insecure_upstream');
  }
  return url.href;
}

export function validateConfig(input, options = {}) {
  if (!input || typeof input !== 'object') throw new Error('invalid_config');
  const config = { ...CONFIG_DEFAULTS, ...input };
  if (config.listen_host !== '127.0.0.1') throw new Error('listen_host_must_be_loopback');
  positiveInteger(config.port, 'port', { allowZero: options.allowPortZero ?? false });
  if (config.port > 65535) throw new Error('invalid_port');
  if (config.mode === 'round_robin') throw new Error('round_robin_not_implemented');
  if (config.mode !== 'failover') throw new Error('invalid_mode');
  if (!Array.isArray(config.accounts) || config.accounts.length === 0) throw new Error('no_accounts');
  const names = new Set();
  for (const account of config.accounts) {
    if (!account || !ACCOUNT_NAME_RE.test(account.name) || typeof account.auth_file !== 'string'
        || (account.label !== undefined && typeof account.label !== 'string')) {
      throw new Error('invalid_account');
    }
    assertSafeAuthPath(account.auth_file);
    if (names.has(account.name)) throw new Error('duplicate_account_name');
    names.add(account.name);
  }
  positiveInteger(config.request_body_limit_bytes, 'request_body_limit_bytes');
  positiveInteger(config.token_refresh_skew_seconds, 'token_refresh_skew_seconds', { allowZero: true });
  positiveInteger(config.default_cooldown_seconds, 'default_cooldown_seconds', { allowZero: true });
  positiveInteger(config.cooldown_safety_margin_seconds, 'cooldown_safety_margin_seconds', { allowZero: true });
  if (typeof config.allow_insecure_upstream !== 'boolean') throw new Error('invalid_allow_insecure_upstream');
  config.upstream_chatgpt_base_url = validateUpstream(
    config.upstream_chatgpt_base_url,
    CONFIG_DEFAULTS.upstream_chatgpt_base_url,
    config.allow_insecure_upstream,
  );
  config.upstream_openai_base_url = validateUpstream(
    config.upstream_openai_base_url,
    CONFIG_DEFAULTS.upstream_openai_base_url,
    config.allow_insecure_upstream,
  );
  const home = options.home ?? os.homedir();
  config.state_file = path.resolve(expandHome(
    config.state_file ?? '~/Library/Application Support/CodexMulti/proxy-state.json', home,
  ));
  config.log_file = config.log_file === null ? null : path.resolve(expandHome(
    config.log_file ?? '~/Library/Logs/CodexMulti/proxy.log', home,
  ));
  const mainAuthFile = path.resolve(home, '.codex/auth.json');
  const authFiles = new Set();
  config.accounts = config.accounts.map((account) => {
    const authFile = path.resolve(expandHome(account.auth_file, home));
    if (path.basename(authFile) !== 'auth.json') throw new Error('invalid_auth_file_name');
    if (authFile === mainAuthFile) throw new Error('main_auth_file_forbidden');
    if (authFiles.has(authFile)) throw new Error('duplicate_auth_file');
    authFiles.add(authFile);
    return {
      name: account.name,
      ...(account.label === undefined ? {} : { label: account.label }),
      auth_file: authFile,
    };
  });
  if (authFiles.has(config.state_file) || (config.log_file && authFiles.has(config.log_file))) {
    throw new Error('runtime_file_conflicts_with_auth');
  }
  return config;
}

export async function loadConfig(configPath, options = {}) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(path.resolve(configPath), 'utf8'));
  } catch {
    throw new Error('invalid_config_file');
  }
  return validateConfig(parsed, options);
}

function routeFor(rawUrl, config) {
  if (typeof rawUrl !== 'string' || !rawUrl.startsWith('/') || rawUrl.startsWith('//')
      || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(rawUrl)) {
    return { kind: 'invalid' };
  }
  const queryIndex = rawUrl.indexOf('?');
  const pathname = queryIndex === -1 ? rawUrl : rawUrl.slice(0, queryIndex);
  if (pathname === '/backend-api/codex' || pathname.startsWith('/backend-api/codex/')) {
    const suffix = rawUrl.slice('/backend-api/codex'.length);
    return { kind: 'upstream', route: pathname, target: `${config.upstream_openai_base_url.replace(/\/$/, '')}${suffix}` };
  }
  if (pathname === '/backend-api' || pathname.startsWith('/backend-api/')) {
    const suffix = rawUrl.slice('/backend-api'.length);
    return { kind: 'upstream', route: pathname, target: `${config.upstream_chatgpt_base_url.replace(/\/$/, '')}${suffix}` };
  }
  if (pathname === '/_proxy' || pathname.startsWith('/_proxy/')) {
    return { kind: 'control', route: pathname };
  }
  return { kind: 'not_found', route: pathname };
}




export function isResponsesTarget(target) {
  try {
    return new URL(target).pathname.endsWith('/codex/responses');
  } catch {
    return false;
  }
}

async function readRequestBody(request, limit) {
  const declared = request.headers['content-length'];
  if (declared !== undefined && (!/^\d+$/.test(declared) || Number(declared) > limit)) {
    throw new Error('request_body_too_large');
  }
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > limit) throw new Error('request_body_too_large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, length);
}

function json(response, status, value) {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': String(body.length),
    'cache-control': 'no-store',
  });
  response.end(body);
}

function isLoopbackRemote(address) {
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1';
}

function exactJsonContentType(request) {
  return String(request.headers['content-type'] ?? '').split(';', 1)[0].trim().toLowerCase() === 'application/json';
}

async function readControlJson(request, options = {}) {
  if (!exactJsonContentType(request)) throw new Error('content_type_required');
  const raw = await readRequestBody(request, 16 * 1024);
  if (raw.length === 0 && options.requireBody) throw new Error('body_must_be_empty_object');
  try {
    return raw.length ? JSON.parse(raw.toString('utf8')) : {};
  } catch {
    throw new Error('invalid_json');
  }
}

export async function createProxy(configInput, options = {}) {
  const initialConfig = options.validated
    ? configInput : validateConfig(configInput, { allowPortZero: true, home: options.home });
  const configPath = options.configPath ? path.resolve(options.configPath) : null;
  if (initialConfig.log_file) {
    await mkdir(path.dirname(initialConfig.log_file), { recursive: true, mode: 0o700 });
    await chmod(path.dirname(initialConfig.log_file), 0o700);
    if (existsSync(initialConfig.log_file)) await chmod(initialConfig.log_file, 0o600);
  }
  const logger = options.logger ?? createLogger(initialConfig.log_file);
  const initialFailover = options.failover ?? new FailoverManager(
    initialConfig.accounts,
    { stateFile: initialConfig.state_file, now: options.now, writer: options.stateWriter },
  );
  const registryOptions = (config, failover) => ({
    now: options.now,
    skewSeconds: config.token_refresh_skew_seconds,
    refreshUrl: options.refreshUrl,
    refreshRequest: options.refreshRequest,
    enforcePermissions: options.enforcePermissions,
    onState: (name, state) => failover.setRefreshing(name, state === AccountState.REFRESHING),
  });
  const initialRegistry = options.registry ?? new AccountRegistry(
    initialConfig.accounts, registryOptions(initialConfig, initialFailover),
  );
  await initialRegistry.initialize();
  for (const duplicate of initialRegistry.duplicateIdentityNames()) {
    logger({
      timestamp: new Date().toISOString(),
      level: 'warn',
      event: 'duplicate_account_identity',
      account_name: duplicate.duplicate,
    });
  }
  await initialFailover.initialize();
  const agents = options.agents ?? createUpstreamAgents();
  let generation = {
    config: initialConfig,
    registry: initialRegistry,
    failover: initialFailover,
    inFlight: new Map(initialConfig.accounts.map((account) => [account.name, 0])),
    activeRequests: 0,
  };
  let reconfiguring = false;
  const reloadMutex = new Mutex();
  const admissionMutex = new Mutex();

  function totalInFlight(current = generation) {
    return current.activeRequests;
  }

  function changeInFlight(current, name, delta) {
    current.inFlight.set(name, (current.inFlight.get(name) ?? 0) + delta);
  }

  async function statusPayload(current = generation) {
    const { config, registry, failover, inFlight } = current;
    await failover.expireCooldowns();
    const state = failover.snapshot();
    const active = await failover.active();
    return {
      version: 2,
      config_path: configPath,
      active,
      cursor: state.cursor,
      in_flight: totalInFlight(current),
      accounts: config.accounts.map(({ name, label, auth_file: authFile }) => ({
        name,
        label: label ?? null,
        auth_file: authFile,
        state: failover.stateOf(name),
        cooldown_until: state.accounts[name].cooldown_until,
        reason: state.accounts[name].reason,
        token_expires_at: registry.tokenExpiresAt(name) === null
          ? null : new Date(registry.tokenExpiresAt(name) * 1000).toISOString(),
        in_flight: inFlight.get(name) ?? 0,
      })),
    };
  }

  function immutableConfig(config) {
    const { accounts: _accounts, ...immutable } = config;
    return immutable;
  }

  function migrationCounts(currentConfig, candidateConfig) {
    const oldByAuthFile = new Map(currentConfig.accounts.map((account) => [account.auth_file, account]));
    const newByAuthFile = new Map(candidateConfig.accounts.map((account) => [account.auth_file, account]));
    let migrated = 0;
    let renamed = 0;
    for (const [authFile, account] of oldByAuthFile) {
      const candidate = newByAuthFile.get(authFile);
      if (!candidate) continue;
      migrated += 1;
      if (candidate.name !== account.name) renamed += 1;
    }
    return {
      added: candidateConfig.accounts.filter(({ auth_file: authFile }) => !oldByAuthFile.has(authFile)).length,
      removed: currentConfig.accounts.filter(({ auth_file: authFile }) => !newByAuthFile.has(authFile)).length,
      renamed,
      migrated,
    };
  }

  async function reloadConfiguration() {
    return await reloadMutex.run(async () => {
      if (!configPath) return { status: 409, body: { error: 'config_reload_unavailable' } };
      const current = generation;
      const initialInFlight = totalInFlight(current);
      if (initialInFlight !== 0) {
        return { status: 409, body: { error: 'proxy_busy', in_flight: initialInFlight } };
      }
      let candidateConfig;
      try {
        candidateConfig = await loadConfig(configPath, {
          allowPortZero: current.config.port === 0,
          home: options.home,
        });
      } catch {
        return { status: 409, body: { error: 'invalid_config_file' } };
      }
      if (!isDeepStrictEqual(immutableConfig(current.config), immutableConfig(candidateConfig))) {
        return { status: 409, body: { error: 'restart_required' } };
      }
      const candidateFailover = new FailoverManager(candidateConfig.accounts, {
        stateFile: candidateConfig.state_file,
        now: options.now,
        writer: options.stateWriter,
      });
      const candidateRegistry = new AccountRegistry(
        candidateConfig.accounts,
        registryOptions(candidateConfig, candidateFailover),
      );
      try {
        await candidateRegistry.initialize();
      } catch {
        return { status: 409, body: { error: 'invalid_credentials' } };
      }
      const entered = await admissionMutex.run(async () => {
        const latestInFlight = totalInFlight(current);
        if (generation !== current || latestInFlight !== 0) return latestInFlight;
        reconfiguring = true;
        return null;
      });
      if (entered !== null) {
        return { status: 409, body: { error: 'proxy_busy', in_flight: entered } };
      }
      try {
        if (options.beforeReloadCommit) await options.beforeReloadCommit();
        const latestInFlight = totalInFlight(current);
        if (latestInFlight !== 0) {
          return { status: 409, body: { error: 'proxy_busy', in_flight: latestInFlight } };
        }
        const counts = migrationCounts(current.config, candidateConfig);
        await candidateFailover.initializeFrom(current.failover.snapshot());
        generation = {
          config: candidateConfig,
          registry: candidateRegistry,
          failover: candidateFailover,
          inFlight: new Map(candidateConfig.accounts.map((account) => [account.name, 0])),
          activeRequests: 0,
        };
        try {
          logger({
            timestamp: new Date().toISOString(),
            level: 'info',
            event: 'config_reloaded',
            ...counts,
          });
        } catch {

        }
      } catch {
        return { status: 500, body: { error: 'config_reload_failed' } };
      } finally {
        reconfiguring = false;
      }
      return { status: 200, body: await statusPayload() };
    });
  }

  async function control(request, response, route) {
    if (!isLoopbackRemote(request.socket.remoteAddress)) return json(response, 403, { error: 'loopback_only' });
    const current = generation;
    if (request.method === 'GET' && route === '/_proxy/status') {
      return json(response, 200, await statusPayload(current));
    }
    if (request.method === 'POST' && route === '/_proxy/reload-config') {
      const body = await readControlJson(request, { requireBody: true });
      if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length !== 0) {
        return json(response, 400, { error: 'body_must_be_empty_object' });
      }
      const result = await reloadConfiguration();
      return json(response, result.status, result.body);
    }
    const { registry, failover, inFlight } = current;
    if (request.method === 'POST' && route === '/_proxy/switch') {
      const body = await readControlJson(request);
      if (typeof body.name !== 'string') return json(response, 400, { error: 'name_required' });
      await failover.switchTo(body.name);
      return json(response, 200, await statusPayload(current));
    }
    const clearCooldownMatch = route.match(/^\/_proxy\/accounts\/([A-Za-z0-9._-]+)\/clear-cooldown$/);
    if (request.method === 'POST' && clearCooldownMatch) {
      const body = await readControlJson(request, { requireBody: true });
      if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length !== 0) {
        return json(response, 400, { error: 'body_must_be_empty_object' });
      }
      const [, name] = clearCooldownMatch;
      if (!registry.accounts.has(name)) return json(response, 404, { error: 'unknown_account' });
      try {
        return json(response, 200, await failover.clearCooldownExplicit(name));
      } catch (error) {
        if (error?.message === 'account_paused' || error?.message === 'account_invalid') {
          return json(response, 409, { error: error.message });
        }
        throw error;
      }
    }
    const match = route.match(/^\/_proxy\/accounts\/([A-Za-z0-9._-]+)\/(pause|reload|refresh)$/);
    if (request.method === 'POST' && match) {
      await readControlJson(request);
      const [, name, action] = match;
      if (!registry.accounts.has(name)) return json(response, 404, { error: 'unknown_account' });
      if (action === 'pause') {
        await failover.pause(name);
        return json(response, 202, {
          name,
          state: AccountState.PAUSED,
          in_flight: inFlight.get(name) ?? 0,
        });
      } else if (action === 'reload') {
        try {
          await registry.reload(name);
          await failover.reloadReady(name);
        } catch {
          await failover.markInvalid(name);
          return json(response, 409, { error: 'invalid_credentials' });
        }
      } else {
        try {
          const credentials = await registry.forceRefresh(name);
          await failover.reloadReady(name);
          return json(response, 200, {
            name,
            result: 'ok',
            access_expires_at: credentials.expiresAt === null
              ? null : new Date(credentials.expiresAt * 1000).toISOString(),
          });
        } catch {
          await failover.markInvalid(name);
          return json(response, 409, {
            name,
            result: 'failed',
            access_expires_at: null,
          });
        }
      }
      return json(response, 200, await statusPayload(current));
    }
    return json(response, 404, { error: 'control_not_found' });
  }

  async function attemptUpstream(current, request, body, target, name) {
    const admitted = await admissionMutex.run(async () => {
      if (reconfiguring || generation !== current) return false;
      changeInFlight(current, name, 1);
      return true;
    });
    if (!admitted) throw new Error('proxy_reconfiguring');
    try {
      const credentials = await current.registry.ensureFresh(name);
      const headers = buildUpstreamHeaders(request.headers, credentials, new URL(target), body.length);
      const opened = await openUpstream({
        method: request.method,
        target,
        headers,
        body,
        agents,
      });
      return { ...opened, credentials };
    } catch (error) {
      changeInFlight(current, name, -1);
      throw error;
    }
  }

  async function finishAttempt(release, work) {
    try {
      return await work();
    } finally {
      release();
    }
  }

  async function proxyRequest(current, request, response, route, body) {
    const admitted = await admissionMutex.run(async () => {
      if (reconfiguring || generation !== current) return false;
      current.activeRequests += 1;
      return true;
    });
    if (!admitted) return json(response, 503, { error: 'proxy_reconfiguring' });
    try {
      return await proxyRequestAdmitted(current, request, response, route, body);
    } finally {
      current.activeRequests -= 1;
    }
  }

  async function proxyRequestAdmitted(current, request, response, route, body) {
    const { config, registry, failover } = current;
    const attempted = new Set();
    let accountName = await failover.selectReady(attempted);
    let cooldownProbe = false;
    if (!accountName) {
      accountName = await failover.earliestCooldown();
      cooldownProbe = Boolean(accountName);
    }
    if (!accountName) return json(response, 503, { error: 'proxy_no_eligible_account' });
    let attemptNumber = 0;
    while (accountName) {
      attemptNumber += 1;
      attempted.add(accountName);
      const started = Date.now();
      let opened;
      try {
        opened = await attemptUpstream(current, request, body, route.target, accountName);
      } catch (error) {
        if (error?.message === 'proxy_reconfiguring') {
          return json(response, 503, { error: 'proxy_reconfiguring' });
        }
        if (String(error?.message).startsWith('credential_')) {
          await failover.markInvalid(accountName);
          return json(response, 503, { error: 'proxy_account_invalid' });
        }
        logger({ timestamp: new Date().toISOString(), level: 'error', event: 'upstream_transport_error',
          request_id: request.proxyRequestId, method: request.method, route: route.route,
          status: 502, duration_ms: Date.now() - started, account_name: accountName, attempt: attemptNumber });
        return json(response, 502, { error: 'proxy_upstream_transport_error' });
      }
      let { request: upstreamRequest, response: upstreamResponse, credentials } = opened;
      request.proxyUpstreamStatus = upstreamResponse.statusCode ?? null;
      const currentAccount = accountName;
      let released = false;
      const releaseAttempt = () => {
        if (released) return;
        released = true;
        changeInFlight(current, currentAccount, -1);
      };
      const relayStream = async (prefix = null) => {
        const result = await finishAttempt(releaseAttempt, () => streamResponse(
          response, upstreamResponse, prefix, upstreamRequest,
        ));
        const common = {
          timestamp: new Date().toISOString(),
          request_id: request.proxyRequestId,
          method: request.method,
          route: route.route,
          upstream_status: upstreamResponse.statusCode ?? null,
          account_name: currentAccount,
          attempt: attemptNumber,
          relayed_bytes: result.relayedBytes,
          duration_ms: Date.now() - request.proxyStarted,
        };
        if (result.outcome === 'client_closed') {
          logger({
            ...common,
            level: 'info',
            event: 'client_closed',
            terminal_seen: result.terminalSeen,
          });
        } else if (result.outcome === 'upstream_stream_error') {
          logger({
            ...common,
            level: 'error',
            event: 'upstream_stream_error',
            error_code: redactSecret(String(result.errorCode ?? 'UPSTREAM_STREAM_ERROR')).slice(0, 100),
          });
        }
        return result;
      };
      try {
        let status = upstreamResponse.statusCode ?? 502;

      if (status === 401 && !cooldownProbe) {
        await discardResponse(upstreamResponse);
        try {
          credentials = await registry.recover401(accountName, credentials.accessToken);
        } catch {
          releaseAttempt();
          await failover.markInvalid(accountName);
          return json(response, 503, { error: 'proxy_account_invalid' });
        }
        const retryHeaders = buildUpstreamHeaders(request.headers, credentials, new URL(route.target), body.length);
        try {
          ({ request: upstreamRequest, response: upstreamResponse } = await openUpstream({
            method: request.method, target: route.target, headers: retryHeaders, body, agents,
          }));
          status = upstreamResponse.statusCode ?? 502;
          request.proxyUpstreamStatus = status;
        } catch {
          releaseAttempt();
          return json(response, 502, { error: 'proxy_upstream_transport_error' });
        }
      }

      if (status === 429) {
        let buffered;
        try {
          buffered = await bufferForClassification(upstreamResponse);
        } catch {
          releaseAttempt();
          return json(response, 502, { error: 'proxy_upstream_stream_error' });
        }
        if (!buffered.complete) {
          return await relayStream(buffered.prefix);
        }
        const classification = classify429(buffered.raw, upstreamResponse.headers, {
          now: options.now ? options.now() : Date.now(),
          defaultSeconds: config.default_cooldown_seconds,
          marginSeconds: config.cooldown_safety_margin_seconds,
        });
        if (classification.usageLimit) {
          await failover.markCooldown(accountName, classification.cooldownUntil);
          logger({ timestamp: new Date().toISOString(), level: 'info', event: 'account_cooldown',
            request_id: request.proxyRequestId, method: request.method, route: route.route,
            status, duration_ms: Date.now() - started, account_name: accountName, attempt: attemptNumber,
            cooldown_until: new Date(classification.cooldownUntil).toISOString() });
          releaseAttempt();
          if (cooldownProbe) {
            return await sendBuffered(response, status, upstreamResponse.headers, buffered.raw);
          }
          accountName = await failover.selectReady(attempted);
          if (accountName) continue;
          accountName = await failover.earliestCooldown();
          cooldownProbe = Boolean(accountName);
          if (accountName) continue;
          return json(response, 503, { error: 'proxy_no_eligible_account' });
        }
        return await finishAttempt(releaseAttempt, () => sendBuffered(
          response, status, upstreamResponse.headers, buffered.raw,
        ));
      }

      if (cooldownProbe && status >= 200 && status < 300 && isResponsesTarget(route.target)) {
        await failover.clearCooldown(accountName);
      }
      return await relayStream();
      } catch (error) {
        releaseAttempt();
        throw error;
      }
    }
  }

  const server = http.createServer(async (request, response) => {
    request.proxyRequestId = randomUUID();
    request.proxyStarted = Date.now();
    const current = generation;
    const route = routeFor(request.url, current.config);
    try {
      if (route.kind === 'invalid') return json(response, 400, { error: 'invalid_request_target' });
      if (route.kind === 'not_found') return json(response, 404, { error: 'not_found' });
      if (route.kind === 'control') return await control(request, response, route.route);
      if (reconfiguring) return json(response, 503, { error: 'proxy_reconfiguring' });
      let body;
      try {
        body = await readRequestBody(request, current.config.request_body_limit_bytes);
      } catch (error) {
        if (error.message === 'request_body_too_large') return json(response, 413, { error: 'request_body_too_large' });
        throw error;
      }
      if (reconfiguring || generation !== current) {
        return json(response, 503, { error: 'proxy_reconfiguring' });
      }
      return await proxyRequest(current, request, response, route, body);
    } catch (error) {
      const clientErrors = new Map([
        ['content_type_required', 415],
        ['invalid_json', 400],
        ['body_must_be_empty_object', 400],
        ['request_body_too_large', 413],
        ['unknown_account', 404],
      ]);
      const clientStatus = route.kind === 'control' ? clientErrors.get(error.message) : null;
      if (!response.headersSent && clientStatus) {
        json(response, clientStatus, { error: error.message });
        return;
      }
      if (!response.headersSent) json(response, 500, { error: 'proxy_internal_error' });
      else response.destroy();
      logger({ timestamp: new Date().toISOString(), level: 'error', event: 'request_error',
        request_id: request.proxyRequestId, method: request.method, route: route.route ?? '/', status: 500,
        error_code: error?.code ?? null,
        error_message: redactSecret(String(error?.message ?? error)).slice(0, 200),
        upstream_status: request.proxyUpstreamStatus ?? null, duration_ms: Date.now() - (request.proxyStarted ?? Date.now()) });
    }
  });
  server.on('upgrade', (request, socket) => {
    socket.end('HTTP/1.1 426 Upgrade Required\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  });

  async function listen() {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(initialConfig.port, initialConfig.listen_host, () => {
        server.off('error', reject);
        resolve();
      });
    });
    return server.address();
  }

  async function close() {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    agents.http.destroy();
    agents.https.destroy();
  }

  return {
    server,
    get config() { return generation.config; },
    get registry() { return generation.registry; },
    get failover() { return generation.failover; },
    listen,
    close,
    statusPayload,
  };
}

export async function serveFromConfig(configPath) {
  const normalizedConfigPath = path.resolve(configPath);
  const config = await loadConfig(normalizedConfigPath);
  const proxy = await createProxy(config, { validated: true, configPath: normalizedConfigPath });
  const address = await proxy.listen();
  process.stdout.write(`codexmulti-proxy listening on 127.0.0.1:${address.port}\n`);
  return proxy;
}

function configArg(argv) {
  const index = argv.indexOf('--config');
  if (index === -1 || !argv[index + 1]) throw new Error('missing_config');
  return argv[index + 1];
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  serveFromConfig(configArg(process.argv.slice(2))).catch((error) => {
    process.stderr.write(`${redactSecret(error.message)}\n`);
    process.exitCode = 1;
  });
}
