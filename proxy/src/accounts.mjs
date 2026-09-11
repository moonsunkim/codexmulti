import http from 'node:http';
import https from 'node:https';
import os from 'node:os';
import path from 'node:path';
import { constants as fsConstants } from 'node:fs';
import {
  chmod,
  lstat,
  mkdir,
  open,
  readFile,
  realpath,
  rename,
  rm,
  stat,
} from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

export const ACCOUNT_NAME_RE = /^[A-Za-z0-9._-]+$/;
export const REFRESH_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
export const DEFAULT_REFRESH_URL = 'https://auth.openai.com/oauth/token';
export const DEFAULT_REFRESH_SKEW_SECONDS = 48 * 60 * 60;

export function expandHome(input, home = os.homedir()) {
  if (input === '~') return home;
  if (input.startsWith('~/')) return path.join(home, input.slice(2));
  return input;
}

export function parseJwtExp(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3 || !parts[1]) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return Number.isFinite(payload.exp) ? Math.trunc(payload.exp) : null;
  } catch {
    return null;
  }
}

export class Mutex {
  #tail = Promise.resolve();

  async run(fn) {
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    const previous = this.#tail;
    this.#tail = previous.then(() => gate, () => gate);
    await previous;
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

export async function ensurePrivateDirectory(directory, { create = false } = {}) {
  if (create) await mkdir(directory, { recursive: true, mode: 0o700 });
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new Error('credential_directory_not_private');
  }
  if ((stat.mode & 0o777) !== 0o700) {
    throw new Error('credential_directory_not_private');
  }
}

export async function atomicWriteJson(file, value, options = {}) {
  const directory = path.dirname(file);
  if (options.createDirectory) {
    await mkdir(directory, { recursive: true, mode: 0o700 });
    await chmod(directory, 0o700);
  }
  const temp = path.join(directory, `.${path.basename(file)}.${process.pid}.${randomUUID()}.tmp`);
  let handle;
  try {
    handle = await open(temp, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, 0o600);
    await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`, 'utf8');
    await handle.sync();
    await handle.close();
    handle = null;
    if (options.beforeRename) await options.beforeRename(temp, file);
    await rename(temp, file);
    const directoryHandle = await open(directory, fsConstants.O_RDONLY);
    try {
      await directoryHandle.sync();
    } finally {
      await directoryHandle.close();
    }
  } catch (error) {
    if (handle) await handle.close().catch(() => {});
    await rm(temp, { force: true }).catch(() => {});
    throw error;
  }
}

function validateAuthShape(auth) {
  if (!auth || typeof auth !== 'object' || auth.auth_mode !== 'chatgpt') {
    throw new Error('invalid_auth_file');
  }
  const tokens = auth.tokens;
  if (!tokens || typeof tokens !== 'object'
      || typeof tokens.access_token !== 'string' || !tokens.access_token
      || typeof tokens.refresh_token !== 'string' || !tokens.refresh_token
      || typeof tokens.account_id !== 'string' || !tokens.account_id) {
    throw new Error('invalid_auth_file');
  }
  return auth;
}

export async function readAuthFile(file, { enforcePermissions = true } = {}) {
  const parent = path.dirname(file);
  if (enforcePermissions) await ensurePrivateDirectory(parent);
  const stat = await lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('invalid_auth_file');
  if (enforcePermissions && (stat.mode & 0o777) !== 0o600) {
    throw new Error('credential_file_not_private');
  }
  const parentReal = await realpath(parent);
  const fileReal = await realpath(file);
  if (path.dirname(fileReal) !== parentReal) throw new Error('auth_path_escape');
  let parsed;
  try {
    parsed = JSON.parse(await readFile(file, 'utf8'));
  } catch {
    throw new Error('invalid_auth_file');
  }
  return validateAuthShape(parsed);
}

async function authFileIdentity(file) {
  const value = await stat(file, { bigint: true });
  if (!value.isFile()) throw new Error('invalid_auth_file');
  return { ino: value.ino, size: value.size, mtimeNs: value.mtimeNs };
}

function sameFileIdentity(left, right) {
  return Boolean(left && right
    && left.ino === right.ino
    && left.size === right.size
    && left.mtimeNs === right.mtimeNs);
}

async function readAuthSnapshot(file, options = {}) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const before = await authFileIdentity(file);
      const auth = await readAuthFile(file, options);
      const after = await authFileIdentity(file);
      if (sameFileIdentity(before, after)) return { auth, identity: after };
      lastError = new Error('auth_file_changed_during_read');
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw lastError ?? new Error('invalid_auth_file');
}

async function collectResponse(response, limit = 1024 * 1024) {
  const chunks = [];
  let length = 0;
  for await (const chunk of response) {
    length += chunk.length;
    if (length > limit) throw new Error('refresh_response_too_large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, length);
}

export async function requestRefresh(refreshUrl, refreshToken, { timeoutMs = 10_000 } = {}) {
  const target = new URL(refreshUrl);
  const transport = target.protocol === 'https:' ? https : target.protocol === 'http:' ? http : null;
  if (!transport) throw new Error('invalid_refresh_url');
  const body = Buffer.from(JSON.stringify({
    client_id: REFRESH_CLIENT_ID,
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
  }));
  return await new Promise((resolve, reject) => {
    const request = transport.request(target, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'content-length': String(body.length),
      },
    }, async (response) => {
      try {
        const raw = await collectResponse(response);
        if ((response.statusCode ?? 500) < 200 || (response.statusCode ?? 500) >= 300) {
          throw new Error('refresh_rejected');
        }
        const payload = JSON.parse(raw.toString('utf8'));
        if (!payload || typeof payload.access_token !== 'string' || !payload.access_token) {
          throw new Error('invalid_refresh_response');
        }
        resolve(payload);
      } catch (error) {
        reject(error);
      }
    });
    request.setTimeout(timeoutMs, () => request.destroy(new Error('refresh_timeout')));
    request.once('error', reject);
    request.end(body);
  });
}

export function assertSafeAuthPath(rawPath) {
  if (typeof rawPath !== 'string' || !rawPath) throw new Error('invalid_auth_path');
  const segments = rawPath.replaceAll('\\', '/').split('/');
  if (segments.includes('..')) throw new Error('auth_path_escape');
}

export class AccountRegistry {
  constructor(accountConfigs, options = {}) {
    this.now = options.now ?? (() => Date.now());
    this.skewSeconds = options.skewSeconds ?? DEFAULT_REFRESH_SKEW_SECONDS;
    this.refreshUrl = options.refreshUrl ?? DEFAULT_REFRESH_URL;
    this.refreshRequest = options.refreshRequest ?? requestRefresh;
    this.atomicWriter = options.atomicWriter ?? atomicWriteJson;
    this.enforcePermissions = options.enforcePermissions ?? true;
    this.onState = options.onState ?? (() => {});
    this.accounts = new Map();
    for (const config of accountConfigs) {
      if (!ACCOUNT_NAME_RE.test(config.name)) throw new Error('invalid_account_name');
      if (this.accounts.has(config.name)) throw new Error('duplicate_account_name');
      assertSafeAuthPath(config.auth_file);
      this.accounts.set(config.name, {
        name: config.name,
        authFile: path.resolve(expandHome(config.auth_file)),
        auth: null,
        fileIdentity: null,
        mutex: new Mutex(),
      });
    }
  }

  names() {
    return [...this.accounts.keys()];
  }

  get(name) {
    const account = this.accounts.get(name);
    if (!account) throw new Error('unknown_account');
    return account;
  }

  async initialize() {
    for (const account of this.accounts.values()) {
      const snapshot = await readAuthSnapshot(account.authFile, {
        enforcePermissions: this.enforcePermissions,
      });
      account.auth = snapshot.auth;
      account.fileIdentity = snapshot.identity;
    }
  }

  credentials(name) {
    const auth = this.get(name).auth;
    if (!auth) throw new Error('account_not_loaded');
    return {
      accessToken: auth.tokens.access_token,
      accountId: auth.tokens.account_id,
      expiresAt: parseJwtExp(auth.tokens.access_token),
    };
  }

  tokenExpiresAt(name) {
    return this.credentials(name).expiresAt;
  }

  duplicateIdentityNames() {
    const firstByIdentity = new Map();
    const duplicates = [];
    for (const account of this.accounts.values()) {
      const identity = account.auth?.tokens?.account_id;
      if (!identity) continue;
      const first = firstByIdentity.get(identity);
      if (first) duplicates.push({ first, duplicate: account.name });
      else firstByIdentity.set(identity, account.name);
    }
    return duplicates;
  }

  async reload(name) {
    const account = this.get(name);
    return await account.mutex.run(async () => {
      await this.#loadSnapshot(account);
      return this.credentials(name);
    });
  }

  async ensureFresh(name) {
    const account = this.get(name);
    await this.#reloadIfChanged(account);
    const current = this.credentials(name);
    const nowSeconds = Math.floor(this.now() / 1000);
    if (current.expiresAt !== null && current.expiresAt > nowSeconds + this.skewSeconds) return current;
    return await account.mutex.run(async () => {
      this.onState(name, 'REFRESHING');
      try {
        await this.#loadSnapshot(account);
        const diskCredentials = this.credentials(name);
        const afterLockNow = Math.floor(this.now() / 1000);
        if (diskCredentials.expiresAt !== null
            && diskCredentials.expiresAt > afterLockNow + this.skewSeconds) {
          return diskCredentials;
        }
        return await this.#refreshLocked(account);
      } finally {
        this.onState(name, null);
      }
    });
  }

  async recover401(name, failedAccessToken) {
    const account = this.get(name);
    return await account.mutex.run(async () => {
      this.onState(name, 'REFRESHING');
      try {
        await this.#loadSnapshot(account);
        if (account.auth.tokens.access_token !== failedAccessToken) return this.credentials(name);
        return await this.#refreshLocked(account);
      } finally {
        this.onState(name, null);
      }
    });
  }

  async forceRefresh(name) {
    const account = this.get(name);
    return await account.mutex.run(async () => {
      this.onState(name, 'REFRESHING');
      try {
        await this.#loadSnapshot(account);
        return await this.#refreshLocked(account);
      } finally {
        this.onState(name, null);
      }
    });
  }

  async #loadSnapshot(account) {
    let snapshot;
    try {
      snapshot = await readAuthSnapshot(account.authFile, {
        enforcePermissions: this.enforcePermissions,
      });
    } catch {
      throw new Error('credential_reload_failed');
    }
    account.auth = snapshot.auth;
    account.fileIdentity = snapshot.identity;
    return snapshot;
  }

  async #reloadIfChanged(account) {
    let identity;
    try {
      identity = await authFileIdentity(account.authFile);
    } catch {
      throw new Error('credential_reload_failed');
    }
    if (sameFileIdentity(identity, account.fileIdentity)) return false;
    return await account.mutex.run(async () => {
      let latest;
      try {
        latest = await authFileIdentity(account.authFile);
      } catch {
        throw new Error('credential_reload_failed');
      }
      if (sameFileIdentity(latest, account.fileIdentity)) return false;
      await this.#loadSnapshot(account);
      return true;
    });
  }

  async #refreshLocked(account) {
    const usedRefreshToken = account.auth.tokens.refresh_token;
    let refreshed;
    try {
      refreshed = await this.refreshRequest(
        this.refreshUrl,
        usedRefreshToken,
      );
    } catch {
      try {
        await this.#loadSnapshot(account);
        const diskCredentials = this.credentials(account.name);
        const nowSeconds = Math.floor(this.now() / 1000);
        if (account.auth.tokens.refresh_token !== usedRefreshToken
            && diskCredentials.expiresAt !== null
            && diskCredentials.expiresAt > nowSeconds) {
          return diskCredentials;
        }
      } catch {

      }
      throw new Error('credential_refresh_failed');
    }
    const updated = structuredClone(account.auth);
    updated.tokens.access_token = refreshed.access_token;
    if (typeof refreshed.refresh_token === 'string' && refreshed.refresh_token) {
      updated.tokens.refresh_token = refreshed.refresh_token;
    }
    if (typeof refreshed.id_token === 'string' && refreshed.id_token) {
      updated.tokens.id_token = refreshed.id_token;
    }
    updated.last_refresh = new Date(this.now()).toISOString();
    const exp = parseJwtExp(updated.tokens.access_token);
    const nowSeconds = Math.floor(this.now() / 1000);
    if (exp === null || exp <= nowSeconds) throw new Error('credential_refresh_failed');
    try {
      await this.atomicWriter(account.authFile, updated);
    } catch {
      throw new Error('credential_save_failed');
    }
    try {
      await this.#loadSnapshot(account);
      const savedCredentials = this.credentials(account.name);
      if (savedCredentials.expiresAt === null || savedCredentials.expiresAt <= nowSeconds) {
        throw new Error('credential_save_failed');
      }
      return savedCredentials;
    } catch {
      throw new Error('credential_save_failed');
    }
  }
}
