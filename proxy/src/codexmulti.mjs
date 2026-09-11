import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import {
  atomicWriteJson,
  expandHome,
  parseJwtExp,
  readAuthFile,
} from './accounts.mjs';
import { CONFIG_DEFAULTS, validateConfig } from './server.mjs';

export const DEFAULT_CODEXMULTI_STORE = '~/Library/Application Support/CodexMulti';
const STORAGE_KEY_RE = /^codex-[0-9a-f]{32}$/;

function isoFromUnixSeconds(value) {
  if (!Number.isFinite(value)) throw new Error('invalid_access_exp');
  const result = new Date(value * 1000);
  if (!Number.isFinite(result.getTime())) throw new Error('invalid_access_exp');
  return result.toISOString();
}

async function readJson(file, errorName) {
  try {
    return JSON.parse(await readFile(file, 'utf8'));
  } catch {
    throw new Error(errorName);
  }
}

async function readExistingConfig(file) {
  try {
    const value = JSON.parse(await readFile(file, 'utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw new Error('invalid_existing_config');
  }
}

function initialConfig(accounts) {
  return {
    listen_host: CONFIG_DEFAULTS.listen_host,
    port: CONFIG_DEFAULTS.port,
    mode: CONFIG_DEFAULTS.mode,
    accounts,
    upstream_chatgpt_base_url: CONFIG_DEFAULTS.upstream_chatgpt_base_url,
    upstream_openai_base_url: CONFIG_DEFAULTS.upstream_openai_base_url,
    request_body_limit_bytes: CONFIG_DEFAULTS.request_body_limit_bytes,
    token_refresh_skew_seconds: CONFIG_DEFAULTS.token_refresh_skew_seconds,
    default_cooldown_seconds: CONFIG_DEFAULTS.default_cooldown_seconds,
    cooldown_safety_margin_seconds: CONFIG_DEFAULTS.cooldown_safety_margin_seconds,
    allow_insecure_upstream: false,
  };
}

export async function importCodexMulti(options = {}) {
  const home = options.home ?? os.homedir();
  const store = path.resolve(expandHome(options.store ?? DEFAULT_CODEXMULTI_STORE, home));
  const out = path.resolve(expandHome(
    options.out ?? '~/.config/codexmulti/proxy.json',
    home,
  ));
  const registry = await readJson(path.join(store, 'accounts.json'), 'invalid_codexmulti_accounts_file');
  if (registry?.schema_version !== 1 || !Array.isArray(registry.accounts)) {
    throw new Error('invalid_codexmulti_accounts_file');
  }

  const selected = registry.accounts.filter((account) => account?.provider === 'codex'
    && account.enabled === true && account.auth_state === 'connected');
  if (selected.length === 0) throw new Error('no_eligible_codexmulti_accounts');

  const rows = [];
  const accounts = [];
  const identityOwners = new Map();
  const warningPairs = new Set();
  for (let index = 0; index < selected.length; index += 1) {
    const source = selected[index];
    const name = `codex-${index + 1}`;
    const label = typeof source.provider_email === 'string' ? source.provider_email : '';
    let accessExpiresAt = null;
    let validation = 'failed';
    let authFile = null;
    try {
      if (!STORAGE_KEY_RE.test(source.storage_key)) throw new Error('invalid_storage_key');
      authFile = path.join(store, 'accounts', source.storage_key, 'codex', 'auth.json');
      const auth = await readAuthFile(authFile);
      const exp = parseJwtExp(auth.tokens.access_token);
      accessExpiresAt = isoFromUnixSeconds(exp);
      validation = 'ok';
      const prior = identityOwners.get(auth.tokens.account_id);
      if (prior) warningPairs.add(`${prior},${name}`);
      else identityOwners.set(auth.tokens.account_id, name);
    } catch {

    }
    rows.push({ name, label, accessExpiresAt, validation });
    accounts.push({ name, label, auth_file: authFile });
  }

  const valid = rows.every((row) => row.validation === 'ok');
  let wrote = false;
  if (valid && !options.dryRun) {
    const existing = await readExistingConfig(out);
    const next = existing ? { ...existing, accounts } : initialConfig(accounts);
    if (accounts.some((account) => path.resolve(account.auth_file) === out)) {
      throw new Error('output_conflicts_with_auth');
    }
    validateConfig(next, { home });
    await (options.writer ?? atomicWriteJson)(out, next, { createDirectory: true });
    wrote = true;
  }

  return {
    ok: valid,
    dryRun: Boolean(options.dryRun),
    wrote,
    out,
    rows,
    warnings: [...warningPairs].map((names) => `duplicate account identity: ${names}`),
  };
}

function safeCell(value) {
  return String(value ?? '-').replace(/[\t\r\n\x00-\x1f\x7f]/g, ' ');
}

export function formatImportTable(rows) {
  const values = [
    ['NAME', 'LABEL', 'ACCESS EXPIRES AT', 'VALIDATION'],
    ...rows.map((row) => [
      row.name,
      row.label || '-',
      row.accessExpiresAt ?? '-',
      row.validation,
    ]),
  ].map((row) => row.map(safeCell));
  const widths = values[0].map((_, column) => Math.max(...values.map((row) => row[column].length)));
  return `${values.map((row) => row.map((cell, column) => cell.padEnd(widths[column])).join('  ').trimEnd()).join('\n')}\n`;
}
