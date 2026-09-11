const account_registry = @import("account_registry.zig");
const domain = @import("domain.zig");
const codex = @import("providers/codex.zig");

const max_accounts: usize = account_registry.max_accounts;
pub const max_windows_per_account: usize = codex.max_usage_windows;
pub const max_credit_details_per_account: usize = codex.max_credit_details;
pub const max_window_label_bytes: usize = 48;
pub const max_credit_id_bytes: usize = codex.max_credit_id_bytes;
pub const max_snapshot_text_bytes: usize =
    max_windows_per_account * 2 * max_window_label_bytes + max_credit_details_per_account * (max_credit_id_bytes + max_window_label_bytes);

pub const Supported = struct {
    status: domain.SnapshotStatus = .fresh,
    observed_at_unix_s: i64,
    windows: []const domain.UsageWindow = &.{},
    reset_credits: ?domain.ResetCreditSummary = null,

    partial_failure: ?domain.RefreshError = null,
};

pub const State = struct {
    present: bool,
    captured_at_unix_s: i64,
    status: domain.SnapshotStatus,
    failure: ?domain.RefreshError,
    window_count: usize,
    windows: []const domain.UsageWindow,
    details: []const domain.ResetCreditDetail,
    credits: ?domain.ResetCreditSummary,
};

const empty_window: domain.UsageWindow = .{ .kind = .other, .label = "", .used_percent = 0 };
const empty_detail: domain.ResetCreditDetail = .{ .id = "", .label = "" };
const TextSpan = struct { start: u16 = 0, len: u16 = 0 };

const SnapshotSlot = struct {
    present: bool = false,
    provider: domain.Provider = .codex,
    captured_at_unix_s: i64 = 0,
    status: domain.SnapshotStatus = .unavailable,
    failure: ?domain.RefreshError = null,

    windows: [max_windows_per_account]domain.UsageWindow = @splat(empty_window),
    window_labels: [max_windows_per_account]TextSpan = @splat(.{}),
    window_models: [max_windows_per_account]?TextSpan = @splat(null),
    window_count: usize = 0,

    details: [max_credit_details_per_account]domain.ResetCreditDetail = @splat(empty_detail),
    detail_ids: [max_credit_details_per_account]TextSpan = @splat(.{}),
    detail_labels: [max_credit_details_per_account]TextSpan = @splat(.{}),
    detail_count: usize = 0,
    credits: ?domain.ResetCreditSummary = null,

    text: [max_snapshot_text_bytes]u8 = @splat(0),
    text_len: u16 = 0,

    dropped: u16 = 0,

    fn clear(self: *SnapshotSlot) void {
        self.* = .{};
    }

    fn textOf(self: *const SnapshotSlot, span: TextSpan) []const u8 {
        return self.text[span.start..][0..span.len];
    }

    fn internLabel(self: *SnapshotSlot, text: []const u8, limit: usize) ?TextSpan {
        const start = self.text_len;
        var written: usize = 0;
        for (text) |byte| {
            if (written == limit) break;
            if (byte < 0x20 or byte > 0x7e) continue;
            if (self.text_len == self.text.len) return null;
            self.text[self.text_len] = byte;
            self.text_len += 1;
            written += 1;
        }
        if (written == 0) return null;
        return .{ .start = start, .len = @intCast(self.text_len - start) };
    }

    fn internIdentifier(self: *SnapshotSlot, text: []const u8, limit: usize) ?TextSpan {
        if (text.len == 0 or text.len > limit) return null;
        for (text) |byte| {
            if (byte < 0x20 or byte > 0x7e) return null;
        }
        if (text.len > self.text.len - self.text_len) return null;
        const start = self.text_len;
        @memcpy(self.text[start..][0..text.len], text);
        self.text_len += @intCast(text.len);
        return .{ .start = start, .len = @intCast(text.len) };
    }

    fn rebind(self: *SnapshotSlot) void {
        var index: usize = 0;
        while (index < self.window_count) : (index += 1) {
            self.windows[index].label = self.textOf(self.window_labels[index]);
            self.windows[index].model_label = if (self.window_models[index]) |span| self.textOf(span) else null;
        }
        index = 0;
        while (index < self.detail_count) : (index += 1) {
            self.details[index].id = self.textOf(self.detail_ids[index]);
            self.details[index].label = self.textOf(self.detail_labels[index]);
        }
        if (self.credits) |*credits| credits.details = self.details[0..self.detail_count];
    }

    fn replace(self: *SnapshotSlot, provider: domain.Provider, observation: Supported, capacity_failure: domain.RefreshError) void {
        self.clear();
        self.present = true;
        self.provider = provider;
        self.captured_at_unix_s = observation.observed_at_unix_s;
        self.status = observation.status;

        for (observation.windows) |window| {
            if (self.window_count == max_windows_per_account) {
                self.dropped += 1;
                continue;
            }
            const label = self.internLabel(window.label, max_window_label_bytes) orelse {
                self.dropped += 1;
                continue;
            };
            const model = if (window.model_label) |text|
                self.internLabel(text, max_window_label_bytes)
            else
                null;
            const index = self.window_count;
            self.window_labels[index] = label;
            self.window_models[index] = model;
            self.windows[index] = .{
                .kind = window.kind,
                .label = "",
                .used_percent = @min(window.used_percent, 100),
                .reset_at_unix_s = window.reset_at_unix_s,
                .duration_minutes = window.duration_minutes,
                .model_label = null,
            };
            self.window_count += 1;
        }

        if (observation.reset_credits) |summary| {
            for (summary.details) |detail| {
                if (self.detail_count == max_credit_details_per_account) {
                    self.dropped += 1;
                    continue;
                }

                if (self.detail_count == summary.available_count) {
                    self.dropped += 1;
                    continue;
                }
                const id = self.internIdentifier(detail.id, max_credit_id_bytes) orelse {
                    self.dropped += 1;
                    continue;
                };
                const label = self.internLabel(detail.label, max_window_label_bytes) orelse
                    self.internLabel("reset credit", max_window_label_bytes) orelse {
                    self.dropped += 1;
                    continue;
                };
                const index = self.detail_count;
                self.detail_ids[index] = id;
                self.detail_labels[index] = label;
                self.details[index] = .{
                    .id = "",
                    .label = "",
                    .expires_at_unix_s = detail.expires_at_unix_s,
                };
                self.detail_count += 1;
            }
            self.credits = .{
                .available_count = summary.available_count,
                .observed_at_unix_s = summary.observed_at_unix_s,
                .detail_status = summary.detail_status,
                .details = &.{},
            };
        }

        self.rebind();

        self.failure = observation.partial_failure;
        if (self.dropped != 0) {
            if (self.status == .fresh) self.status = .partial;
            if (self.failure == null) self.failure = capacity_failure;
        }
    }

    fn snapshot(self: *const SnapshotSlot, account_id: []const u8) ?domain.UsageSnapshot {
        if (!self.present) return null;
        return .{
            .account_id = account_id,
            .provider = self.provider,
            .captured_at_unix_s = self.captured_at_unix_s,
            .status = self.status,
            .windows = self.windows[0..self.window_count],
            .reset_credits = self.credits,
            .refresh_error = self.failure,
        };
    }

    fn mostConstrainingWindow(self: *const SnapshotSlot) ?domain.UsageWindow {
        if (!self.present or self.window_count == 0) return null;
        var best: usize = 0;
        var index: usize = 1;
        while (index < self.window_count) : (index += 1) {
            const candidate = self.windows[index];
            const current = self.windows[best];
            if (candidate.used_percent > current.used_percent) {
                best = index;
                continue;
            }
            if (candidate.used_percent < current.used_percent) continue;
            const candidate_reset = candidate.reset_at_unix_s orelse continue;
            const current_reset = current.reset_at_unix_s orelse {
                best = index;
                continue;
            };
            if (candidate_reset < current_reset) best = index;
        }
        return self.windows[best];
    }
};

pub const SnapshotBook = struct {
    slots: [max_accounts]SnapshotSlot = @splat(.{}),
    revision: u64 = 0,

    pub fn revisionValue(self: *const SnapshotBook) u64 {
        return self.revision;
    }

    pub fn stateAt(self: *const SnapshotBook, index: usize) State {
        const slot = &self.slots[index];
        return .{
            .present = slot.present,
            .captured_at_unix_s = slot.captured_at_unix_s,
            .status = slot.status,
            .failure = slot.failure,
            .window_count = slot.window_count,
            .windows = slot.windows[0..slot.window_count],
            .details = slot.details[0..slot.detail_count],
            .credits = slot.credits,
        };
    }

    pub fn snapshotAt(self: *const SnapshotBook, index: usize, account_id: []const u8) ?domain.UsageSnapshot {
        return self.slots[index].snapshot(account_id);
    }

    pub fn mostConstrainingWindowAt(self: *const SnapshotBook, index: usize) ?domain.UsageWindow {
        return self.slots[index].mostConstrainingWindow();
    }

    pub fn replace(self: *SnapshotBook, index: usize, provider: domain.Provider, observation: Supported, capacity_failure: domain.RefreshError) void {
        self.slots[index].replace(provider, observation, capacity_failure);
        self.revision +%= 1;
    }

    pub fn restore(self: *SnapshotBook, index: usize, provider: domain.Provider, observation: Supported, capacity_failure: domain.RefreshError) void {
        self.slots[index].replace(provider, observation, capacity_failure);
    }

    pub fn finishRestore(self: *SnapshotBook) void {
        self.revision +%= 1;
    }

    pub fn clear(self: *SnapshotBook) void {
        for (&self.slots) |*slot| slot.clear();
        self.revision +%= 1;
    }

    pub fn move(self: *SnapshotBook, from: usize, to: usize) void {
        if (from == to) return;
        const moved = self.slots[from];
        if (from < to) {
            var index = from;
            while (index < to) : (index += 1) self.adopt(index, index + 1);
        } else {
            var index = from;
            while (index > to) : (index -= 1) self.adopt(index, index - 1);
        }
        self.slots[to] = moved;
        self.slots[to].rebind();
    }

    pub fn remove(self: *SnapshotBook, index: usize) void {
        var cursor = index;
        while (cursor + 1 < max_accounts) : (cursor += 1) self.adopt(cursor, cursor + 1);
        self.slots[max_accounts - 1].clear();
        self.revision +%= 1;
    }

    fn adopt(self: *SnapshotBook, destination: usize, source: usize) void {
        self.slots[destination] = self.slots[source];
        self.slots[destination].rebind();
    }
};
