import http from 'node:http';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { loadConfig, redactSecret, serveFromConfig } from './server.mjs';
import { readControlToken } from './control-auth.mjs';
import { DEFAULT_CODEXMULTI_STORE, formatImportTable, importCodexMulti } from './codexmulti.mjs';

function usage() {
  return [
    'usage: codexmulti-proxy [--config PATH] <serve|status|switch|pause|reload|refresh|login> [name]',
    '       codexmulti-proxy status [--labels] [--config PATH]',
    '       codexmulti-proxy pause <name> [--wait [seconds]] [--config PATH]',
    '       codexmulti-proxy clear-cooldown <name> [--config PATH]',
    '       codexmulti-proxy import-codexmulti [--store DIR] [--out PATH] [--dry-run]',
    '',
  ].join('\n');
}

function parseArgs(argv) {
  let configPath = path.join(os.homedir(), '.config/codexmulti/proxy.json');
  let storePath = DEFAULT_CODEXMULTI_STORE;
  let outPath = null;
  let dryRun = false;
  let labels = false;
  let waitSeconds = null;
  let usedStore = false;
  let usedOut = false;
  const args = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === '--config') {
      if (!argv[index + 1]) throw new Error('missing_config');
      configPath = argv[index + 1];
      index += 1;
    } else if (argv[index] === '--store') {
      if (!argv[index + 1] || usedStore) throw new Error('invalid_store_option');
      storePath = argv[index + 1];
      usedStore = true;
      index += 1;
    } else if (argv[index] === '--out') {
      if (!argv[index + 1] || usedOut) throw new Error('invalid_out_option');
      outPath = argv[index + 1];
      usedOut = true;
      index += 1;
    } else if (argv[index] === '--dry-run') {
      if (dryRun) throw new Error('invalid_dry_run_option');
      dryRun = true;
    } else if (argv[index] === '--labels') {
      if (labels) throw new Error('invalid_labels_option');
      labels = true;
    } else if (argv[index] === '--wait') {
      if (waitSeconds !== null) throw new Error('invalid_wait_option');
      waitSeconds = 60;
      const candidate = argv[index + 1];
      if (candidate !== undefined && /^\d+(?:\.\d+)?$/.test(candidate)) {
        const seconds = Number(candidate);
        if (!Number.isFinite(seconds) || seconds <= 0 || seconds > 86_400) {
          throw new Error('invalid_wait_option');
        }
        waitSeconds = seconds;
        index += 1;
      }
    } else {
      args.push(argv[index]);
    }
  }
  return {
    configPath,
    command: args[0],
    name: args[1],
    extra: args.slice(2),
    storePath,
    outPath: outPath ?? configPath,
    dryRun,
    labels,
    waitSeconds,
    usedStore,
    usedOut,
  };
}

async function controlRequest(config, method, requestPath, body = null) {
  const payload = body === null ? null : Buffer.from(JSON.stringify(body));
  let token = null;
  if (config.control_token_file) {
    try {
      token = await readControlToken(config.control_token_file);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return await new Promise((resolve, reject) => {
    const request = http.request({
      hostname: config.listen_host,
      port: config.port,
      path: requestPath,
      method,
      headers: {
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(payload ? { 'content-type': 'application/json', 'content-length': String(payload.length) } : {}),
      },
    }, async (response) => {
      const chunks = [];
      let length = 0;
      try {
        for await (const chunk of response) {
          length += chunk.length;
          if (length > 1024 * 1024) throw new Error('control_response_too_large');
          chunks.push(chunk);
        }
        const value = JSON.parse(Buffer.concat(chunks, length).toString('utf8'));
        if ((response.statusCode ?? 500) >= 400) {
          const error = new Error(value.error ?? 'control_request_failed');
          error.statusCode = response.statusCode;
          error.responseBody = value;
          throw error;
        }
        resolve(value);
      } catch (error) {
        reject(error);
      }
    });
    request.once('error', reject);
    request.setTimeout(2_000, () => request.destroy(new Error('proxy_unreachable')));
    request.end(payload);
  });
}

function cliStatus(status, includeLabels) {
  return {
    ...status,
    accounts: status.accounts.map(({ label, auth_file: _authFile, ...account }) => ({
      ...account,
      ...(includeLabels ? { label: label ?? null } : {}),
    })),
  };
}

async function waitForAccountDrain(config, name, seconds, dependencies = {}) {
  const requestControl = dependencies.controlRequest ?? controlRequest;
  const now = dependencies.now ?? (() => Date.now());
  const sleep = dependencies.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
  const deadline = now() + seconds * 1000;
  while (true) {
    const status = await requestControl(config, 'GET', '/_proxy/status');
    const account = status.accounts.find((candidate) => candidate.name === name);
    if (!account) throw new Error('unknown_account');
    if (account.in_flight === 0) return status;
    const remaining = deadline - now();
    if (remaining <= 0) throw new Error('pause_wait_timeout');
    await sleep(Math.min(100, remaining));
  }
}

async function runLogin(config, name, dependencies = {}) {
  const account = config.accounts.find((candidate) => candidate.name === name);
  if (!account) throw new Error('unknown_account');
  let proxyOnline = false;
  const requestControl = dependencies.controlRequest ?? controlRequest;
  try {
    await requestControl(config, 'GET', '/_proxy/status');
    proxyOnline = true;
  } catch (error) {
    if (error.message !== 'proxy_unreachable' && error.code !== 'ECONNREFUSED') throw error;
  }
  if (proxyOnline) {
    await requestControl(config, 'POST', `/_proxy/accounts/${encodeURIComponent(name)}/pause`, {});
    await waitForAccountDrain(config, name, dependencies.loginWaitSeconds ?? 60, dependencies);
  }
  const spawnImpl = dependencies.spawn ?? spawn;
  const code = await new Promise((resolve, reject) => {
    const child = spawnImpl('codex', ['login'], {
      stdio: 'inherit',
      env: { ...process.env, CODEX_HOME: path.dirname(account.auth_file) },
    });
    child.once('error', reject);
    child.once('exit', (exitCode, signal) => resolve(signal ? 1 : exitCode ?? 1));
  });
  if (code !== 0) throw new Error('codex_login_failed');
  if (proxyOnline) {
    return await requestControl(config, 'POST', `/_proxy/accounts/${encodeURIComponent(name)}/reload`, {});
  }
  return { login: 'complete', account: name };
}

export async function main(argv = process.argv.slice(2), dependencies = {}) {
  const parsed = parseArgs(argv);
  const {
    configPath, command, name, extra, storePath, outPath, dryRun, labels, waitSeconds, usedStore, usedOut,
  } = parsed;
  if (!command || extra.length) throw new Error('invalid_arguments');
  const stdout = dependencies.stdout ?? process.stdout;
  const stderr = dependencies.stderr ?? process.stderr;
  if (command === 'import-codexmulti') {
    if (name || labels || waitSeconds !== null) throw new Error('invalid_arguments');
    const imported = await (dependencies.importCodexMulti ?? importCodexMulti)({
      store: storePath,
      out: outPath,
      dryRun,
    });
    stdout.write(formatImportTable(imported.rows));
    for (const warning of imported.warnings) stderr.write(`warning: ${warning}\n`);
    return imported.ok ? 0 : 1;
  }
  if (dryRun || usedStore || usedOut || (waitSeconds !== null && command !== 'pause')) {
    throw new Error('invalid_arguments');
  }
  if (command === 'serve') {
    if (name || labels || waitSeconds !== null) throw new Error('invalid_arguments');
    await (dependencies.serveFromConfig ?? serveFromConfig)(configPath);
    return 0;
  }
  const config = await (dependencies.loadConfig ?? loadConfig)(configPath);
  const requestControl = dependencies.controlRequest ?? controlRequest;
  let result;
  let exitCode = 0;
  if (command === 'status') {
    if (name) throw new Error('invalid_arguments');
    result = cliStatus(await requestControl(config, 'GET', '/_proxy/status'), labels);
  } else if (command === 'switch' && name) {
    if (labels) throw new Error('invalid_arguments');
    result = await requestControl(config, 'POST', '/_proxy/switch', { name });
  } else if ((command === 'pause' || command === 'reload' || command === 'clear-cooldown') && name) {
    if (labels) throw new Error('invalid_arguments');
    result = await requestControl(config, 'POST', `/_proxy/accounts/${encodeURIComponent(name)}/${command}`, {});
    if (command === 'pause' && waitSeconds !== null) {
      result = await waitForAccountDrain(config, name, waitSeconds, dependencies);
    }
  } else if (command === 'refresh' && name) {
    if (labels) throw new Error('invalid_arguments');
    try {
      result = await requestControl(config, 'POST', `/_proxy/accounts/${encodeURIComponent(name)}/refresh`, {});
    } catch (error) {
      if (error.statusCode !== 409 || error.responseBody?.result !== 'failed') throw error;
      result = {
        name: error.responseBody.name,
        result: 'failed',
        access_expires_at: null,
      };
      exitCode = 1;
    }
  } else if (command === 'login' && name) {
    if (labels) throw new Error('invalid_arguments');
    result = await runLogin(config, name, dependencies);
  } else {
    throw new Error('invalid_arguments');
  }
  stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return exitCode;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().then((exitCode) => {
    if (exitCode) process.exitCode = exitCode;
  }).catch((error) => {
    process.stderr.write(`${redactSecret(error.message)}\n${usage()}`);
    process.exitCode = 1;
  });
}

export { cliStatus, controlRequest, parseArgs, runLogin, waitForAccountDrain };
