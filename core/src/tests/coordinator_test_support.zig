const std = @import("std");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
const runtime_paths = @import("../runtime_paths.zig");
const transport = @import("../process_jsonl.zig");
const codex = @import("../providers/codex.zig");

const testing = std.testing;

pub const fixture_now: i64 = 2_000_000_000;

pub const home_dir = "/demo/home/demo-user";
pub const app_root = home_dir ++ "/Library/Application Support/" ++ runtime_paths.app_data_directory_name;
pub const accounts_root = app_root ++ "/accounts";

pub const codex_account_id = "acct-codex-demo";
pub const claude_account_id = "acct-claude-demo";
pub const codex_storage_key = "codex-demo";
pub const claude_storage_key = "claude-demo";
pub const codex_home = accounts_root ++ "/" ++ codex_storage_key ++ "/codex";
pub const codex_profile_dir = accounts_root ++ "/" ++ codex_storage_key;
pub const claude_config_dir = accounts_root ++ "/" ++ claude_storage_key ++ "/claude";

pub const codex_executable = "/demo/bin/codex";
pub const claude_executable = "/demo/bin/claude";

pub const canary_access = "demo-access-placeholder-1111";
pub const canary_refresh = "demo-refresh-placeholder-0000";
pub const canary_identity = "demo-identity-should-not-leak";

pub const claude_usage_url = "https://usage.example.invalid/v1/usage";

pub const RecordingSink = struct {
    const max_records: usize = 24;
    const max_bytes: usize = 32 * 1024;

    const Record = struct { kind: runtime_paths.DocumentKind, start: usize, len: usize };

    records: [max_records]Record = @splat(.{ .kind = .registry, .start = 0, .len = 0 }),
    record_count: usize = 0,
    bytes: [max_bytes]u8 = @splat(0),
    bytes_len: usize = 0,

    fail_kind: ?runtime_paths.DocumentKind = null,
    fail_error: coordinator.SinkError = error.Io,
    fail_after_matches: usize = 0,
    matches: usize = 0,

    const vtable: coordinator.DocumentSink.VTable = .{ .write = write };

    pub fn create() !*RecordingSink {
        const value = try testing.allocator.create(RecordingSink);
        value.* = .{};
        return value;
    }

    pub fn destroy(self: *RecordingSink) void {
        testing.allocator.destroy(self);
    }

    pub fn sink(self: *RecordingSink) coordinator.DocumentSink {
        return .{ .context = self, .vtable = &vtable };
    }

    fn write(context: *anyopaque, kind: runtime_paths.DocumentKind, bytes: []const u8) coordinator.SinkError!void {
        const self: *RecordingSink = @ptrCast(@alignCast(context));
        if (self.fail_kind) |failing| {
            if (failing == kind) {
                self.matches += 1;
                if (self.matches > self.fail_after_matches) return self.fail_error;
            }
        }
        if (self.record_count == max_records) return error.TooLarge;
        if (bytes.len > max_bytes - self.bytes_len) return error.TooLarge;
        const start = self.bytes_len;
        @memcpy(self.bytes[start..][0..bytes.len], bytes);
        self.bytes_len += bytes.len;
        self.records[self.record_count] = .{ .kind = kind, .start = start, .len = bytes.len };
        self.record_count += 1;
    }

    pub fn countOf(self: *const RecordingSink, kind: runtime_paths.DocumentKind) usize {
        var count: usize = 0;
        for (self.records[0..self.record_count]) |record| {
            if (record.kind == kind) count += 1;
        }
        return count;
    }

    pub fn lastOf(self: *const RecordingSink, kind: runtime_paths.DocumentKind) ?[]const u8 {
        var index = self.record_count;
        while (index > 0) {
            index -= 1;
            const record = self.records[index];
            if (record.kind == kind) return self.bytes[record.start..][0..record.len];
        }
        return null;
    }

    pub fn allBytes(self: *const RecordingSink) []const u8 {
        return self.bytes[0..self.bytes_len];
    }

    pub fn reset(self: *RecordingSink) void {
        self.record_count = 0;
        self.bytes_len = 0;
        self.matches = 0;
    }
};

pub const FakeLifecycle = struct {
    inner: transport.FakeChildLifecycle = .{},

    const vtable: coordinator.ChildLifecycle.VTable = .{ .close = close };

    pub fn lifecycle(self: *FakeLifecycle) coordinator.ChildLifecycle {
        return .{ .context = self, .vtable = &vtable };
    }

    fn close(context: *anyopaque) void {
        const self: *FakeLifecycle = @ptrCast(@alignCast(context));
        self.inner.close();
    }
};

pub const CodexHarness = struct {
    stream: transport.FakeStream,
    storage: [transport.max_frame_bytes]u8,
    connection: transport.Connection,
    workspace: codex.Workspace,
    lifecycle: FakeLifecycle,

    pub fn create(chunks: []const transport.FakeStream.Chunk) !*CodexHarness {
        const harness = try testing.allocator.create(CodexHarness);
        harness.stream = .{ .chunks = chunks };
        harness.workspace = .{};
        harness.lifecycle = .{};
        harness.connection = .init(&harness.storage, harness.stream.stream());
        return harness;
    }

    pub fn destroy(self: *CodexHarness) void {
        testing.allocator.destroy(self);
    }

    pub fn live(self: *CodexHarness, home: []const u8, close_when_done: bool) coordinator.LiveAdapters {
        return .{ .codex = .{
            .adapter = .{ .config = .{ .codex_home = home } },
            .connection = &self.connection,
            .workspace = &self.workspace,
            .lifecycle = self.lifecycle.lifecycle(),
            .close_when_done = close_when_done,
        } };
    }

    pub fn adapter(_: *CodexHarness, home: []const u8) codex.Adapter {
        return .{ .config = .{ .codex_home = home } };
    }
};

pub fn testLayout() !runtime_paths.Layout {
    return runtime_paths.Layout.fromHomeDir(home_dir);
}

pub fn newCoordinator() !*coordinator.Coordinator {
    return coordinator.Coordinator.create(testing.allocator, .{
        .layout = try testLayout(),
        .target = .{
            .codex_executable = codex_executable,
            .codex_cli_version = "0.145.0",
        },
    });
}

pub fn seedAccounts(app: *coordinator.Coordinator) !void {
    _ = try app.addAccount(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Codex Demo",
        .storage_key = codex_storage_key,
        .created_at_unix_s = fixture_now - 10_000,
    });
    _ = try app.addAccount(.{
        .id = claude_account_id,
        .provider = .claude,
        .label = "Claude Demo",
        .storage_key = claude_storage_key,
        .created_at_unix_s = fixture_now - 10_000,
    });
    _ = try app.registry.markConnected(codex_account_id, null);
    _ = try app.registry.markConnected(claude_account_id, null);
}

pub const demo_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "Current session", .used_percent = 24, .reset_at_unix_s = fixture_now + 3600, .duration_minutes = 300 },
    .{ .kind = .weekly, .label = "Current week", .used_percent = 61, .reset_at_unix_s = fixture_now + 86_400, .duration_minutes = 10_080 },
};

pub const demo_details = [_]domain.ResetCreditDetail{
    .{ .id = "credit-demo-b", .label = "Later reset", .expires_at_unix_s = fixture_now + 600_000 },
    .{ .id = "credit-demo-a", .label = "Earlier reset", .expires_at_unix_s = fixture_now + 300_000 },
};

pub fn demoCredits(count: u32) domain.ResetCreditSummary {
    return .{
        .available_count = count,
        .observed_at_unix_s = fixture_now,
        .detail_status = .detailed,
        .details = &demo_details,
    };
}

pub fn supportedObservation(now_unix_s: i64, credits: ?domain.ResetCreditSummary) coordinator.Observation {
    return .{ .supported = .{
        .status = .fresh,
        .observed_at_unix_s = now_unix_s,
        .windows = &demo_windows,
        .reset_credits = credits,
    } };
}

pub fn admit(app: *coordinator.Coordinator, account_id: []const u8, now_unix_s: i64) !coordinator.Ticket {
    _ = try app.requestRefresh(account_id);
    return app.nextOperation(now_unix_s) orelse error.NotAdmitted;
}

pub fn runPreflight(
    app: *coordinator.Coordinator,
    session: *coordinator.ResetSession,
    harness: *CodexHarness,
    sink: coordinator.DocumentSink,
    now_unix_s: i64,
) !coordinator.RefreshReport {
    const ticket = try app.beginSessionStep(session, .reset_preflight, now_unix_s);
    return app.runRefresh(ticket, harness.live(codex_home, false), now_unix_s, sink);
}
