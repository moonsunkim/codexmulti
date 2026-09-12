import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { Mutex } from './accounts.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KINDS = ['http', 'websocket', 'renewal', 'control'];

function sameSecret(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

export class UpdateGate {
  constructor({ context = null, now = () => performance.now(), leaseMs = 10_000 } = {}) {
    this.context = context;
    this.now = now;
    this.leaseMs = leaseMs;
    this.bootId = randomUUID();
    this.mode = context?.gated ? 'gated' : 'serving';
    this.generation = context?.generation ?? 0;
    this.work = Object.fromEntries(KINDS.map((kind) => [kind, 0]));
    this.lease = null;
    this.commands = new Mutex();
    this.idleWaiters = new Set();
    this.activation = null;
  }

  total() { return Object.values(this.work).reduce((sum, count) => sum + count, 0); }

  expire() {
    if (this.mode !== 'quiescent' || !this.lease || this.now() < this.lease.deadline) return;
    try {
      if (this.context.canResume(this.lease)) {
        this.mode = 'serving';
        this.lease = null;
      }
    } catch {
    }
  }

  enter(kind) {
    if (!KINDS.includes(kind)) throw new Error('invalid_work_kind');
    this.expire();
    if (this.mode !== 'serving') return null;
    this.work[kind] += 1;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.work[kind] -= 1;
      if (this.total() === 0) {
        for (const resolve of this.idleWaiters) resolve();
        this.idleWaiters.clear();
      }
    };
  }

  whenIdle() {
    if (this.total() === 0) return Promise.resolve();
    return new Promise((resolve) => this.idleWaiters.add(resolve));
  }

  beginShutdown() { this.mode = 'stopped'; }

  health() {
    this.expire();
    return {
      update_protocol: 1,
      managed: this.context !== null,
      runtime_id: this.context?.runtimeId ?? null,
      boot_id: this.bootId,
      generation: this.generation,
      gate: this.mode,
      config_revision: this.context?.configRevision() ?? null,
      work: { ...this.work },
      work_total: this.total(),
      payload_verified: this.context?.verified === true,
    };
  }

  assertIdentity(body) {
    if (!this.context) throw new Error('runtime_unmanaged');
    if (!body || !UUID.test(body.transaction_id) || !Number.isSafeInteger(body.epoch) || body.epoch < 1
        || body.boot_id !== this.bootId || body.runtime_id !== this.context.runtimeId) {
      throw new Error('update_identity_mismatch');
    }
  }

  assertLease(body, { committedStop = false } = {}) {
    const lease = this.lease;
    if (!lease || lease.transaction_id !== body.transaction_id || lease.epoch !== body.epoch
        || !sameSecret(lease.token, body.lease)) throw new Error('update_lease_mismatch');
    if (!committedStop && this.mode !== 'stopped' && this.now() >= lease.deadline) throw new Error('update_lease_expired');
    return lease;
  }

  async command(action, body) {
    return await this.commands.run(async () => {
      try {
        this.expire();
        this.assertIdentity(body);
        this.context.authorize(action, body);
        if (action === 'prepare-if-idle') {
          if (this.mode === 'quiescent' && this.lease?.transaction_id === body.transaction_id
              && this.lease.epoch === body.epoch) {
            return this.preparedReply();
          }
          if (this.mode !== 'serving') throw new Error('proxy_update_fenced');
          if (body.config_revision !== this.context.configRevision()) throw new Error('config_revision_changed');
          if (this.total() !== 0) return { status: 409, body: { error: 'proxy_busy', ...this.health() } };
          this.mode = 'quiescent';
          this.lease = {
            transaction_id: body.transaction_id, epoch: body.epoch, boot_id: this.bootId,
            token: randomBytes(32).toString('hex'), deadline: this.now() + this.leaseMs,
            config_revision: body.config_revision,
          };
          return this.preparedReply();
        }
        if (action === 'activate') {
          if (this.mode === 'stopped') throw new Error('proxy_update_fenced');
          if (!Number.isSafeInteger(body.generation) || body.generation < 1
              || !this.context.canActivate(body)) throw new Error('activation_not_committed');
          if (this.activation && this.activation.generation === body.generation
              && this.activation.transaction_id === body.transaction_id && this.activation.epoch === body.epoch) {
            return { status: 200, body: this.health() };
          }
          if (this.mode !== 'gated' || body.generation < this.generation) throw new Error('activation_generation_mismatch');
          await this.context.beforeActivate?.();
          if (!this.context.canActivate(body)) throw new Error('activation_not_committed');
          this.generation = body.generation;
          this.activation = { ...body };
          this.mode = 'serving';
          return { status: 200, body: this.health() };
        }
        const lease = this.assertLease(body, {
          committedStop: action === 'commit-stop' && this.context.stopCommitted(body),
        });
        if (action === 'renew-lease') {
          if (this.mode !== 'quiescent' || !this.context.canResume(lease)) throw new Error('stop_already_committed');
          lease.deadline = this.now() + this.leaseMs;
          return this.preparedReply();
        }
        if (action === 'abort-prepare') {
          if (this.mode !== 'quiescent' || !this.context.canResume(lease)) throw new Error('stop_already_committed');
          this.lease = null;
          this.mode = 'serving';
          return { status: 200, body: this.health() };
        }
        if (action === 'commit-stop') {
          if (this.total() !== 0 || lease.config_revision !== this.context.configRevision()
              || !this.context.stopCommitted(body)) throw new Error('stop_not_committed');
          this.mode = 'stopped';
          return { status: 200, body: this.health() };
        }
        return { status: 404, body: { error: 'update_command_not_found' } };
      } catch (error) {
        const code = /^[a-z][a-z0-9_]{0,79}$/.test(error.message) ? error.message : 'update_unavailable';
        return { status: 409, body: { error: code } };
      }
    });
  }

  preparedReply() {
    return { status: 200, body: {
      ...this.health(), lease: this.lease.token,
      lease_remaining_ms: Math.max(0, this.lease.deadline - this.now()),
    } };
  }
}
