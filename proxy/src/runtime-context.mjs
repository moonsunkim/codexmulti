import path from 'node:path';
import { constants, closeSync, fstatSync, lstatSync, openSync, readFileSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';

const digestPattern = /^[a-f0-9]{64}$/;
const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const oldMayServe = new Set(['PREPARING_APP', 'APP_PREPARED', 'INSTALLING_APP', 'AWAITING_GUI',
  'WAITING_IDLE', 'COMPLETE', 'CANCELLED', 'ROLLED_BACK', 'APP_RECOVERY_REQUIRED']);
const terminal = new Set(['COMPLETE', 'CANCELLED', 'ROLLED_BACK', 'RECOVERY_REQUIRED', 'APP_RECOVERY_REQUIRED']);
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

function safePath(file, { directory = false, privateFile = false } = {}) {
  const info = lstatSync(file);
  if (info.uid !== process.getuid() || (info.mode & (privateFile ? 0o077 : 0o022)) !== 0
      || !(directory ? info.isDirectory() : info.isFile()) || realpathSync(file) !== path.resolve(file)) {
    throw new Error('runtime_path_not_private');
  }
  return info;
}

function readJSON(file, { privateFile = true } = {}) {
  safePath(file, { privateFile });
  const descriptor = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = fstatSync(descriptor);
    if (!info.isFile() || info.size > 1_048_576 || info.uid !== process.getuid()
        || (info.mode & (privateFile ? 0o077 : 0o022)) !== 0) throw new Error('invalid_runtime_state');
    return JSON.parse(readFileSync(descriptor, 'utf8'));
  } finally {
    closeSync(descriptor);
  }
}

export function loadRuntimeContext(configPath, environment = process.env) {
  if (!environment.CODEXMULTI_RUNTIME_ROOT && !environment.CODEXMULTI_RUNTIME_APP
      && !environment.CODEXMULTI_RUNTIME_LOCK_FD) return null;
  const root = path.resolve(environment.CODEXMULTI_RUNTIME_ROOT ?? '');
  const app = path.resolve(environment.CODEXMULTI_RUNTIME_APP ?? '');
  safePath(root, { directory: true, privateFile: true });
  safePath(app, { directory: true });
  const manifest = readJSON(path.join(app, 'Contents/Resources/runtime-manifest.json'), { privateFile: false });
  if (manifest.schema !== 1 || !digestPattern.test(manifest.runtime_id) || manifest.update_protocol !== 1
      || manifest.config_schema !== 1 || manifest.state_schema !== 1
      || app !== path.join(root, 'runtimes', manifest.runtime_id, 'CodexMulti.app')) {
    throw new Error('invalid_runtime_manifest');
  }
  const descriptor = Number(environment.CODEXMULTI_RUNTIME_LOCK_FD);
  if (!Number.isSafeInteger(descriptor) || descriptor < 3) throw new Error('runtime_writer_lock_missing');
  const held = fstatSync(descriptor);
  const expected = safePath(path.join(root, 'runtime-writer.lock'), { privateFile: true });
  if (held.dev !== expected.dev || held.ino !== expected.ino || held.uid !== process.getuid()) {
    throw new Error('runtime_writer_lock_mismatch');
  }
  const node = path.join(app, 'Contents/Helpers/node');
  if (realpathSync(process.execPath) !== node) throw new Error('runtime_node_mismatch');
  safePath(node);
  if (digest(readFileSync(node)) !== manifest.node_signed_sha256) throw new Error('runtime_payload_mismatch');
  const proxy = path.join(app, 'Contents/Resources/proxy');
  if (!manifest.proxy_files || Object.keys(manifest.proxy_files).length === 0) throw new Error('invalid_runtime_manifest');
  for (const [relative, hash] of Object.entries(manifest.proxy_files)) {
    if (!(relative === 'package.json' || /^(bin|src)\//.test(relative)) || relative.split('/').includes('..')
        || !digestPattern.test(hash)) throw new Error('invalid_runtime_manifest');
    const file = path.join(proxy, relative);
    safePath(file);
    if (digest(readFileSync(file)) !== hash) throw new Error('runtime_payload_mismatch');
  }

  const readActive = () => {
    const active = readJSON(path.join(root, 'active-runtime.json'));
    if (active.schema !== 1 || !digestPattern.test(active.runtime_id) || !Number.isSafeInteger(active.generation)
        || active.generation < 1) throw new Error('invalid_active_runtime');
    return active;
  };
  const readCurrent = () => {
    let pointer;
    try { pointer = readJSON(path.join(root, 'current-update.json')); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    if (pointer.schema !== 1 || !uuidPattern.test(pointer.transaction_id)) throw new Error('invalid_update_pointer');
    const journal = readJSON(path.join(root, 'updates', pointer.transaction_id, 'journal.json'));
    if (journal.schema !== 1 || journal.transaction_id !== pointer.transaction_id
        || !Number.isSafeInteger(journal.epoch) || journal.epoch < 1) throw new Error('invalid_update_journal');
    return journal;
  };
  const active = readActive();
  const journal = readCurrent();
  if (journal && !terminal.has(journal.phase)) {
    if (![journal.old_runtime_id, journal.target_runtime_id].includes(manifest.runtime_id)
        || journal.config_path !== configPath) throw new Error('runtime_transaction_mismatch');
  } else if (active.runtime_id !== manifest.runtime_id) {
    throw new Error('inactive_runtime');
  }
  const matches = (journal, body) => journal && journal.transaction_id === body.transaction_id && journal.epoch === body.epoch;
  return {
    runtimeId: manifest.runtime_id,
    verified: true,
    generation: active.generation,
    gated: active.runtime_id !== manifest.runtime_id || (journal && !oldMayServe.has(journal.phase)),
    configRevision: () => {
      safePath(configPath, { privateFile: true });
      return digest(readFileSync(configPath));
    },
    authorize: (action, body) => {
      const current = readCurrent();
      if (!matches(current, body) || current.config_path !== configPath
          || ![current.old_runtime_id, current.target_runtime_id].includes(manifest.runtime_id)) {
        throw new Error('runtime_transaction_mismatch');
      }
      const boot = action === 'activate' ? current.candidate_boot_id : current.expected_boot_id;
      if (boot !== body.boot_id) throw new Error('runtime_boot_mismatch');
      if (action === 'prepare-if-idle' && !['WAITING_IDLE', 'QUIESCENT'].includes(current.phase)) {
        throw new Error('prepare_not_authorized');
      }
    },
    canResume: (lease) => {
      const current = readCurrent();
      const selected = readActive();
      return matches(current, lease) && (oldMayServe.has(current.phase) || current.phase === 'QUIESCENT')
        && selected.runtime_id === manifest.runtime_id && selected.generation === active.generation;
    },
    stopCommitted: (body) => {
      const current = readCurrent();
      return matches(current, body) && current.phase === 'STOP_COMMITTED' && current.expected_boot_id === body.boot_id;
    },
    canActivate: (body) => {
      const current = readCurrent();
      const selected = readActive();
      return matches(current, body) && ['ACTIVATION_COMMITTED', 'VERIFYING', 'COMPLETE', 'ROLLED_BACK'].includes(current.phase)
        && current.candidate_boot_id === body.boot_id && current.activation_generation === body.generation
        && selected.runtime_id === manifest.runtime_id && selected.generation === body.generation
        && selected.transaction_id === body.transaction_id && selected.epoch === body.epoch;
    },
  };
}
