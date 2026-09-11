const account_registry = @import("account_registry.zig");
const domain = @import("domain.zig");

const max_accounts: usize = account_registry.max_accounts;

pub const max_concurrent_operations: usize = 2;
pub const max_operations_per_account: usize = 1;

pub const Purpose = enum {
    user_refresh,

    sign_in_refresh,

    reset_preflight,

    reset_post_read,
};

pub const AdmitError = error{
    UnknownAccount,
    AccountDisabled,

    AccountBusy,

    ConcurrencyLimit,
};

pub const Ticket = struct {
    operation_id: u64,
    account_index: u16,
    account_id: []const u8,
    provider: domain.Provider,
    started_at_unix_s: i64,
    purpose: Purpose,

    retains_account: bool = false,
};

pub const EnqueueOutcome = enum { queued, already_pending };

pub const RefreshAllPlan = struct {
    queued: usize = 0,
    already_pending: usize = 0,
    skipped_disabled: usize = 0,

    pub fn total(self: RefreshAllPlan) usize {
        return self.queued + self.already_pending + self.skipped_disabled;
    }
};

pub const Runtime = struct {
    refresh: domain.RefreshState = .{},
    last_attempt_at_unix_s: ?i64 = null,
    last_success_at_unix_s: ?i64 = null,
    last_attempt_code: ?[]const u8 = null,
    queued: bool = false,
    queued_purpose: Purpose = .user_refresh,
    reserved: bool = false,
};

pub const OperationScheduler = struct {
    runtimes: [max_accounts]Runtime = @splat(.{}),
    queue: [max_accounts]u16 = @splat(0),
    queue_head: usize = 0,
    queue_len: usize = 0,
    in_flight: usize = 0,
    next_operation_id: u64 = 1,

    pub fn runtimeAt(self: *OperationScheduler, index: usize) *Runtime {
        return &self.runtimes[index];
    }

    pub fn runtimeAtConst(self: *const OperationScheduler, index: usize) *const Runtime {
        return &self.runtimes[index];
    }

    pub fn inFlightCount(self: *const OperationScheduler) usize {
        return self.in_flight;
    }

    pub fn queuedCount(self: *const OperationScheduler) usize {
        return self.queue_len;
    }

    pub fn isIdle(self: *const OperationScheduler) bool {
        return self.in_flight == 0 and self.queue_len == 0;
    }

    pub fn enqueue(self: *OperationScheduler, index: usize, purpose: Purpose) AdmitError!EnqueueOutcome {
        const runtime = &self.runtimes[index];

        if (runtime.reserved or runtime.queued) return .already_pending;
        if (self.queue_len == max_accounts) return error.ConcurrencyLimit;
        const tail = (self.queue_head + self.queue_len) % max_accounts;
        self.queue[tail] = @intCast(index);
        self.queue_len += 1;
        runtime.queued = true;
        runtime.queued_purpose = purpose;
        return .queued;
    }

    pub fn reserveAccount(self: *OperationScheduler, account_count: usize, index: usize) AdmitError!void {
        if (index >= account_count) return error.UnknownAccount;
        const runtime = &self.runtimes[index];
        if (runtime.reserved) return error.AccountBusy;
        if (self.in_flight >= max_concurrent_operations) return error.ConcurrencyLimit;
        runtime.reserved = true;
        self.in_flight += 1;
    }

    pub fn releaseAccount(self: *OperationScheduler, index: usize) void {
        if (index >= max_accounts) return;
        const runtime = &self.runtimes[index];
        if (!runtime.reserved) return;
        runtime.reserved = false;
        if (self.in_flight != 0) self.in_flight -= 1;
    }

    pub fn takeOperationId(self: *OperationScheduler) u64 {
        const operation_id = self.next_operation_id;
        self.next_operation_id +%= 1;
        return operation_id;
    }

    pub fn nextOperation(self: *OperationScheduler, registry: *const account_registry.Registry, now_unix_s: i64) ?Ticket {
        while (self.queue_len != 0) {
            if (self.in_flight >= max_concurrent_operations) return null;
            const index = self.queue[self.queue_head];
            self.queue_head = (self.queue_head + 1) % max_accounts;
            self.queue_len -= 1;
            if (index >= registry.accountCount()) continue;
            const purpose = self.runtimes[index].queued_purpose;
            self.runtimes[index].queued = false;
            self.runtimes[index].queued_purpose = .user_refresh;
            return self.beginOperation(registry, index, purpose, now_unix_s, false) catch continue;
        }
        return null;
    }

    pub fn moveRuntime(self: *OperationScheduler, from: usize, to: usize) void {
        if (from == to) return;
        const moved = self.runtimes[from];
        if (from < to) {
            var index = from;
            while (index < to) : (index += 1) self.runtimes[index] = self.runtimes[index + 1];
        } else {
            var index = from;
            while (index > to) : (index -= 1) self.runtimes[index] = self.runtimes[index - 1];
        }
        self.runtimes[to] = moved;
    }

    pub fn removeRuntime(self: *OperationScheduler, index: usize) void {
        var cursor = index;
        while (cursor + 1 < max_accounts) : (cursor += 1) self.runtimes[cursor] = self.runtimes[cursor + 1];
        self.runtimes[max_accounts - 1] = .{};
    }

    pub fn clearRuntimes(self: *OperationScheduler) void {
        for (&self.runtimes) |*runtime| runtime.* = .{};
    }

    fn beginOperation(
        self: *OperationScheduler,
        registry: *const account_registry.Registry,
        index: usize,
        purpose: Purpose,
        now_unix_s: i64,
        retains_account: bool,
    ) AdmitError!Ticket {
        const value = registry.at(index) orelse return error.UnknownAccount;
        if (!value.enabled) return error.AccountDisabled;
        try self.reserveAccount(registry.accountCount(), index);
        const runtime = &self.runtimes[index];
        const operation_id = self.takeOperationId();
        runtime.refresh.begin(operation_id, now_unix_s) catch {
            self.releaseAccount(index);
            return error.AccountBusy;
        };
        runtime.last_attempt_at_unix_s = now_unix_s;
        runtime.last_attempt_code = null;
        return .{
            .operation_id = operation_id,
            .account_index = @intCast(index),
            .account_id = value.id,
            .provider = value.provider,
            .started_at_unix_s = now_unix_s,
            .purpose = purpose,
            .retains_account = retains_account,
        };
    }
};
