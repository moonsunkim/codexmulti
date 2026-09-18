import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { atomicWriteJson, Mutex } from './accounts.mjs';

export const AccountState = Object.freeze({
  READY: 'READY',
  COOLDOWN: 'COOLDOWN',
  PAUSED: 'PAUSED',
  INVALID: 'INVALID',
  REFRESHING: 'REFRESHING',
});

function normalizeAccounts(accounts) {
  if (!Array.isArray(accounts) || accounts.length === 0) throw new Error('no_accounts');
  const names = new Set();
  const authFiles = new Set();
  return accounts.map((account) => {
    const normalized = typeof account === 'string'
      ? { name: account, auth_file: null }
      : { name: account?.name, auth_file: account?.auth_file ?? null, auto_select_enabled: account?.auto_select_enabled };
    if (typeof normalized.name !== 'string' || !normalized.name || names.has(normalized.name)) {
      throw new Error('invalid_account');
    }
    if (normalized.auth_file !== null
        && (typeof normalized.auth_file !== 'string' || authFiles.has(normalized.auth_file))) {
      throw new Error('invalid_account');
    }
    names.add(normalized.name);
    if (normalized.auth_file !== null) authFiles.add(normalized.auth_file);
    return normalized;
  });
}

function accountState(account) {
  return {
    ...(account.auth_file === null ? {} : { auth_file: account.auth_file }),
    auto_select_enabled: account.auto_select_enabled ?? true,
    paused: false,
    cooldown_until: null,
    reason: null,
  };
}

function initialState(accounts, now) {
  return {
    version: 1,
    cursor: accounts[0].name,
    selection_source: 'automatic',
    manual_account: null,
    selection_revision: 0,
    accounts: Object.fromEntries(accounts.map((account) => [account.name, accountState(account)])),
    updated_at: new Date(now).toISOString(),
  };
}

function validateState(state) {
  if (!state || state.version !== 1 || typeof state.accounts !== 'object'
      || state.accounts === null || Array.isArray(state.accounts)
      || typeof state.cursor !== 'string' || !Object.hasOwn(state.accounts, state.cursor)
      || typeof state.updated_at !== 'string' || !Number.isFinite(Date.parse(state.updated_at))) {
    throw new Error('invalid_state_file');
  }
  if ((state.selection_source !== undefined && !['automatic', 'manual'].includes(state.selection_source))
      || (state.manual_account != null && !Object.hasOwn(state.accounts, state.manual_account))
      || (state.selection_revision !== undefined && (!Number.isSafeInteger(state.selection_revision) || state.selection_revision < 0))) {
    throw new Error('invalid_state_file');
  }
  const entries = Object.entries(state.accounts);
  if (entries.length === 0) throw new Error('invalid_state_file');
  let authFileShape = null;
  const authFiles = new Set();
  for (const [name, value] of entries) {
    if (!name || !value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('invalid_state_file');
    }
    const hasAuthFile = Object.hasOwn(value, 'auth_file');
    if (authFileShape === null) authFileShape = hasAuthFile;
    if (authFileShape !== hasAuthFile) throw new Error('invalid_state_file');
    if (hasAuthFile && (typeof value.auth_file !== 'string' || !value.auth_file
        || authFiles.has(value.auth_file))) {
      throw new Error('invalid_state_file');
    }
    if (hasAuthFile) authFiles.add(value.auth_file);
    if ((value.auto_select_enabled !== undefined && typeof value.auto_select_enabled !== 'boolean')
        || !value || typeof value.paused !== 'boolean'
        || !(value.cooldown_until === null || typeof value.cooldown_until === 'string')
        || !(value.reason === null || typeof value.reason === 'string')) {
      throw new Error('invalid_state_file');
    }
    if (value.cooldown_until !== null && !Number.isFinite(Date.parse(value.cooldown_until))) {
      throw new Error('invalid_state_file');
    }
  }
  return { state, legacy: authFileShape === false };
}

function migrateState(previous, accounts, now, { legacy = false } = {}) {
  const previousEntries = Object.entries(previous.accounts);
  const previousByAuthFile = legacy ? null : new Map(
    previousEntries.map(([name, value]) => [value.auth_file, { name, value }]),
  );
  const migrated = initialState(accounts, now);
  for (const account of accounts) {
    const source = legacy
      ? (Object.hasOwn(previous.accounts, account.name)
        ? { name: account.name, value: previous.accounts[account.name] } : null)
      : previousByAuthFile.get(account.auth_file);
    if (!source) continue;
    migrated.accounts[account.name] = {
      ...(account.auth_file === null ? {} : { auth_file: account.auth_file }),
      auto_select_enabled: account.auto_select_enabled ?? source.value.auto_select_enabled ?? !source.value.paused,
      paused: source.value.paused,
      cooldown_until: source.value.cooldown_until,
      reason: source.value.reason,
    };
  }
  const previousCursor = previous.accounts[previous.cursor];
  const cursorOwner = legacy
    ? accounts.find(({ name }) => name === previous.cursor)
    : accounts.find(({ auth_file }) => auth_file === previousCursor.auth_file);
  migrated.cursor = cursorOwner?.name ?? accounts[0].name;
  const manualOwner = accounts.find((account) => legacy
    ? account.name === previous.manual_account
    : account.auth_file === previous.accounts[previous.manual_account]?.auth_file);
  if (previous.selection_source === 'manual' && manualOwner) {
    const value = migrated.accounts[manualOwner.name];
    if (!value.paused && value.reason !== 'invalid_credentials'
        && (!value.cooldown_until || Date.parse(value.cooldown_until) <= now)) {
      migrated.selection_source = 'manual';
      migrated.manual_account = manualOwner.name;
    }
  }
  migrated.selection_revision = previous.selection_revision ?? 0;
  migrated.updated_at = previous.updated_at;
  return migrated;
}

export class FailoverManager {
  constructor(accounts, options = {}) {
    this.accountConfigs = normalizeAccounts(accounts);
    this.names = this.accountConfigs.map(({ name }) => name);
    this.stateFile = options.stateFile ? path.resolve(options.stateFile) : null;
    this.now = options.now ?? (() => Date.now());
    this.writer = options.writer ?? atomicWriteJson;
    this.state = initialState(this.accountConfigs, this.now());
    this.refreshing = new Set();
    this.invalid = new Set();
    this.mutex = new Mutex();
  }

  async initialize({ readOnly = false } = {}) {
    if (!this.stateFile) return;
    try {
      const raw = await readFile(this.stateFile, 'utf8');
      const validated = validateState(JSON.parse(raw));
      this.state = migrateState(validated.state, this.accountConfigs, this.now(), {
        legacy: validated.legacy,
      });
      this.#restoreInvalid();
      const normalized = JSON.stringify(this.state);
      if (!readOnly && (validated.legacy || normalized !== JSON.stringify(validated.state))) await this.#saveLocked();
    } catch (error) {
      if (error?.code !== 'ENOENT') throw new Error('invalid_state_file');
      if (!readOnly) await this.#saveLocked();
    }
  }

  async initializeFrom(previousState) {
    return await this.mutex.run(async () => {
      const validated = validateState(previousState);
      this.state = migrateState(validated.state, this.accountConfigs, this.now(), {
        legacy: validated.legacy,
      });
      this.#restoreInvalid();
      await this.#saveLocked();
      return this.snapshot();
    });
  }

  #restoreInvalid() {
    this.invalid.clear();
    for (const name of this.names) {
      if (this.state.accounts[name].reason === 'invalid_credentials') this.invalid.add(name);
    }
  }

  setRefreshing(name, value) {
    if (value) this.refreshing.add(name);
    else this.refreshing.delete(name);
  }

  stateOf(name) {
    const value = this.state.accounts[name];
    if (!value) throw new Error('unknown_account');
    if (this.refreshing.has(name)) return AccountState.REFRESHING;
    if (this.invalid.has(name)) return AccountState.INVALID;
    if (value.paused) return AccountState.PAUSED;
    if (value.cooldown_until && Date.parse(value.cooldown_until) > this.now()) {
      return AccountState.COOLDOWN;
    }
    return AccountState.READY;
  }

  async expireCooldowns() {
    return await this.mutex.run(async () => {
      let changed = false;
      for (const name of this.names) {
        const value = this.state.accounts[name];
        if (value.cooldown_until && Date.parse(value.cooldown_until) <= this.now()) {
          value.cooldown_until = null;
          if (value.reason === 'usage_limit_reached') value.reason = null;
          changed = true;
        }
      }
      if (changed) await this.#saveLocked();
      return changed;
    });
  }

  #orderedFromCursor() {
    const start = this.names.indexOf(this.state.cursor);
    return [...this.names.slice(start), ...this.names.slice(0, start)];
  }

  #readyForSelection(name) {
    const value = this.state.accounts[name];
    if (this.invalid.has(name) || value.paused) return false;
    return !value.cooldown_until || Date.parse(value.cooldown_until) <= this.now();
  }

  isSelectable(name, { cooldownProbe = false } = {}) {
    const value = this.state.accounts[name];
    if (!value || this.invalid.has(name) || value.paused) return false;
    const manual = this.state.manual_account;
    if (manual && this.#readyForSelection(manual) && manual !== name) return false;
    if (cooldownProbe) return value.auto_select_enabled && this.stateOf(name) === AccountState.COOLDOWN;
    return this.#readyForSelection(name)
      && (value.auto_select_enabled || this.state.manual_account === name);
  }

  async selectReady(excluded = new Set()) {
    await this.expireCooldowns();
    return this.peekActive(excluded);
  }

  async active() {
    return await this.selectReady();
  }

  peekActive(excluded = new Set()) {
    const manual = this.state.manual_account;
    if (manual && !excluded.has(manual) && this.#readyForSelection(manual)) return manual;
    return this.#orderedFromCursor().find((name) => !excluded.has(name)
      && this.state.accounts[name].auto_select_enabled && this.#readyForSelection(name)) ?? null;
  }

  #clearManual(name, revision = this.state.selection_revision) {
    if (this.state.manual_account !== name || revision !== this.state.selection_revision) return;
    this.state.manual_account = null;
    this.state.selection_source = 'automatic';
    this.state.selection_revision += 1;
  }

  async setAutoSelect(name, enabled) {
    if (!this.names.includes(name)) throw new Error('unknown_account');
    if (typeof enabled !== 'boolean') throw new Error('invalid_auto_select_enabled');
    await this.mutex.run(async () => {
      const previous = this.snapshot();
      this.state.accounts[name].auto_select_enabled = enabled;
      try { await this.#saveLocked(); } catch (error) { this.state = previous; throw error; }
    });
  }

  async returnToAutomatic() {
    await this.mutex.run(async () => {
      const previous = this.snapshot();
      this.state.manual_account = null;
      this.state.selection_source = 'automatic';
      this.state.selection_revision += 1;
      try { await this.#saveLocked(); } catch (error) { this.state = previous; throw error; }
    });
    return await this.active();
  }

  async resume(name) {
    await this.mutex.run(async () => {
      const value = this.state.accounts[name];
      if (!value) throw new Error('unknown_account');
      value.paused = false;
      if (value.reason === 'operator_paused') value.reason = null;
      await this.#saveLocked();
    });
  }

  async earliestCooldown() {
    await this.expireCooldowns();
    const candidates = this.names
      .filter((name) => this.state.accounts[name].auto_select_enabled && this.stateOf(name) === AccountState.COOLDOWN)
      .map((name) => ({ name, at: Date.parse(this.state.accounts[name].cooldown_until) }))
      .sort((a, b) => a.at - b.at || this.names.indexOf(a.name) - this.names.indexOf(b.name));
    return candidates[0]?.name ?? null;
  }

  async markCooldown(name, until, selectionRevision = this.state.selection_revision) {
    await this.mutex.run(async () => {
      const value = this.state.accounts[name];
      value.cooldown_until = new Date(until).toISOString();
      value.reason = 'usage_limit_reached';
      this.#clearManual(name, selectionRevision);
      await this.#saveLocked();
    });
  }

  async clearCooldown(name) {
    await this.mutex.run(async () => {
      const value = this.state.accounts[name];
      value.cooldown_until = null;
      if (value.reason === 'usage_limit_reached') value.reason = null;
      await this.#saveLocked();
    });
  }




  async clearCooldownExplicit(name) {
    if (!Object.hasOwn(this.state.accounts, name)) throw new Error('unknown_account');
    return await this.mutex.run(async () => {
      const value = this.state.accounts[name];
      if (this.invalid.has(name)) throw new Error('account_invalid');
      if (value.paused) throw new Error('account_paused');
      value.cooldown_until = null;
      if (value.reason === 'usage_limit_reached') value.reason = null;
      await this.#saveLocked();
      return { name, state: this.stateOf(name), cooldown_until: value.cooldown_until };
    });
  }

  async markInvalid(name, selectionRevision = this.state.selection_revision) {
    await this.mutex.run(async () => {
      this.invalid.add(name);
      this.#clearManual(name, selectionRevision);
      this.state.accounts[name].reason = 'invalid_credentials';
      await this.#saveLocked();
    });
  }

  async clearInvalid(name) {
    await this.mutex.run(async () => {
      if (!this.invalid.delete(name)) return;
      const value = this.state.accounts[name];
      if (value.reason === 'invalid_credentials') value.reason = null;
      await this.#saveLocked();
    });
  }

  async reloadReady(name) {
    await this.mutex.run(async () => {
      this.invalid.delete(name);
      const value = this.state.accounts[name];
      if (value.reason === 'invalid_credentials') value.reason = null;
      await this.#saveLocked();
    });
  }

  async pause(name) {
    await this.mutex.run(async () => {
      const value = this.state.accounts[name];
      if (!value) throw new Error('unknown_account');
      value.paused = true;
      value.reason = 'operator_paused';
      this.#clearManual(name);
      await this.#saveLocked();
    });
  }

  async switchTo(name) {
    if (!this.names.includes(name)) throw new Error('unknown_account');
    await this.mutex.run(async () => {
      if (!this.#readyForSelection(name)) throw new Error('account_not_ready');
      const previous = this.snapshot();
      this.state.cursor = name;
      this.state.manual_account = name;
      this.state.selection_source = 'manual';
      this.state.selection_revision += 1;
      try { await this.#saveLocked(); } catch (error) { this.state = previous; throw error; }
    });
    return await this.active();
  }

  snapshot() {
    return structuredClone(this.state);
  }

  async #saveLocked() {
    this.state.updated_at = new Date(this.now()).toISOString();
    if (this.stateFile) {
      await this.writer(this.stateFile, this.state, { createDirectory: true });
    }
  }
}

function headerValue(headers, name) {
  const value = headers[name.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
}

export function calculateCooldownUntil({ body, headers = {}, now = Date.now(), defaultSeconds = 1800, marginSeconds = 60 }) {
  const nowSeconds = Math.floor(now / 1000);
  const bodyReset = Number(body?.error?.resets_at);
  let resetSeconds = Number.isFinite(bodyReset) && bodyReset > nowSeconds ? bodyReset : null;
  if (resetSeconds === null) {
    const familyRaw = headerValue(headers, 'x-codex-active-limit');
    const family = typeof familyRaw === 'string' && /^[A-Za-z0-9_-]+$/.test(familyRaw)
      ? familyRaw.toLowerCase() : 'codex';
    const reached = String(headerValue(headers, 'x-codex-rate-limit-reached-type') ?? '').toLowerCase();
    if (reached === 'primary' || reached === 'secondary') {
      const candidate = Number(headerValue(headers, `x-${family}-${reached}-reset-at`));
      if (Number.isFinite(candidate) && candidate > nowSeconds) resetSeconds = candidate;
    }
  }
  if (resetSeconds === null) resetSeconds = nowSeconds + defaultSeconds;
  return (resetSeconds + marginSeconds) * 1000;
}
