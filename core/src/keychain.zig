const std = @import("std");
const domain = @import("domain.zig");

pub const max_account_key_bytes: usize = 96;
pub const max_account_label_bytes: usize = max_account_key_bytes + 16;

pub const max_credential_bytes: usize = 16 * 1024;

const mask_bytes: usize = 32;

pub const AccountKeyError = error{ EmptyAccountKey, AccountKeyTooLong, InvalidAccountKey };

pub const AccountKey = struct {
    bytes: [max_account_key_bytes]u8 = @splat(0),
    len: u8 = 0,

    pub fn init(storage_key: []const u8) AccountKeyError!AccountKey {
        if (storage_key.len == 0) return error.EmptyAccountKey;
        if (storage_key.len > max_account_key_bytes) return error.AccountKeyTooLong;
        if (storage_key[0] == '.' or storage_key[storage_key.len - 1] == '.') return error.InvalidAccountKey;
        if (std.mem.indexOf(u8, storage_key, "..") != null) return error.InvalidAccountKey;
        for (storage_key) |byte| {
            if (!isAccountKeyByte(byte)) return error.InvalidAccountKey;
        }
        var key: AccountKey = .{};
        @memcpy(key.bytes[0..storage_key.len], storage_key);
        key.len = @intCast(storage_key.len);
        return key;
    }

    pub fn fromProfile(profile: domain.AccountProfile) AccountKeyError!AccountKey {
        return init(profile.storage_key);
    }

    pub fn slice(self: *const AccountKey) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: *const AccountKey, other: *const AccountKey) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }

    pub fn format(self: AccountKey, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const key = self;
        try writer.writeAll(key.bytes[0..key.len]);
    }
};

fn isAccountKeyByte(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => true,
        else => false,
    };
}

pub const CredentialKind = enum {
    access_token,
    refresh_token,
    staged_refresh_token,

    codex_cli_record,
    codex_auth_backup,

    pub fn slotName(self: CredentialKind) []const u8 {
        return switch (self) {
            .access_token => "access",
            .refresh_token => "refresh",
            .staged_refresh_token => "refresh-staged",
            .codex_cli_record => "codex-cli",
            .codex_auth_backup => "codex-auth",
        };
    }
};

pub fn accountLabel(account: *const AccountKey, kind: CredentialKind, buffer: []u8) error{BufferTooSmall}![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    writer.print("{s}.{s}", .{ account.slice(), kind.slotName() }) catch return error.BufferTooSmall;
    return writer.buffered();
}

var mask_counter: std.atomic.Value(u64) = .init(0x9E37_79B9_7F4A_7C15);

fn freshMask() [mask_bytes]u8 {
    const seed = mask_counter.fetchAdd(0x9E37_79B9_7F4A_7C15, .monotonic);
    var prng: std.Random.DefaultPrng = .init(seed);
    var mask: [mask_bytes]u8 = undefined;
    prng.random().bytes(&mask);

    if (std.mem.allEqual(u8, &mask, 0)) mask[0] = 0x5A;
    return mask;
}

pub const CredentialError = error{SecretTooLong};

pub const Credential = struct {
    masked: [max_credential_bytes]u8 = @splat(0),
    mask: [mask_bytes]u8 = @splat(0),
    len: u16 = 0,

    pub const empty: Credential = .{};

    pub fn init(secret: []const u8) CredentialError!Credential {
        var credential: Credential = .{};
        try credential.set(secret);
        return credential;
    }

    pub fn reset(self: *Credential) void {
        self.mask = freshMask();
        self.len = 0;

        for (&self.masked, 0..) |*byte, index| byte.* = self.mask[index % mask_bytes];
    }

    pub fn append(self: *Credential, chunk: []const u8) CredentialError!void {
        if (chunk.len > max_credential_bytes - self.len) return error.SecretTooLong;
        for (chunk, self.len..) |byte, index| {
            self.masked[index] = byte ^ self.mask[index % mask_bytes];
        }
        self.len += @intCast(chunk.len);
    }

    pub fn set(self: *Credential, secret: []const u8) CredentialError!void {
        if (secret.len > max_credential_bytes) return error.SecretTooLong;
        self.reset();
        try self.append(secret);
    }

    pub fn copyFrom(self: *Credential, other: *const Credential) void {
        self.* = other.*;
    }

    pub fn length(self: *const Credential) usize {
        return self.len;
    }

    pub fn isEmpty(self: *const Credential) bool {
        return self.len == 0;
    }

    pub fn byteAt(self: *const Credential, index: usize) u8 {
        std.debug.assert(index < self.len);
        return self.masked[index] ^ self.mask[index % mask_bytes];
    }

    pub fn copyPlaintext(self: *const Credential, out: []u8) error{BufferTooSmall}![]u8 {
        if (out.len < self.len) return error.BufferTooSmall;
        var index: usize = 0;
        while (index < self.len) : (index += 1) out[index] = self.byteAt(index);
        return out[0..self.len];
    }

    pub fn eql(self: *const Credential, other: *const Credential) bool {
        var diff: u8 = 0;
        var index: usize = 0;
        while (index < max_credential_bytes) : (index += 1) {
            const mine = self.masked[index] ^ self.mask[index % mask_bytes];
            const theirs = other.masked[index] ^ other.mask[index % mask_bytes];
            diff |= mine ^ theirs;
        }
        return diff == 0 and self.len == other.len;
    }

    pub fn eqlPlaintext(self: *const Credential, plaintext: []const u8) bool {
        if (plaintext.len != self.len) return false;
        var diff: u8 = 0;
        for (plaintext, 0..) |byte, index| diff |= byte ^ self.byteAt(index);
        return diff == 0;
    }

    pub fn wipe(self: *Credential) void {
        std.crypto.secureZero(u8, self.masked[0..]);
        std.crypto.secureZero(u8, self.mask[0..]);
        self.len = 0;
    }

    pub fn format(_: *const Credential, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("[redacted credential]");
    }

    pub fn jsonStringify(_: *const Credential, stringify: anytype) !void {
        try stringify.write("[redacted]");
    }
};

pub const LoadError = error{
    Unsupported,
    NotFound,

    AccessDenied,

    RepairRequired,

    Unavailable,

    ValueTooLarge,

    Corrupt,
    Io,
};

pub const SaveError = error{
    Unsupported,
    AccessDenied,
    RepairRequired,
    Unavailable,
    ValueTooLarge,
    StoreFull,
    Io,
};

pub const RemoveError = error{
    Unsupported,
    AccessDenied,
    RepairRequired,
    Unavailable,
    Io,
};

pub const StoreError = LoadError || SaveError || RemoveError;

pub const CredentialStore = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        load: *const fn (context: *anyopaque, account: *const AccountKey, kind: CredentialKind, out: *Credential) LoadError!void,

        contains: *const fn (context: *anyopaque, account: *const AccountKey, kind: CredentialKind) LoadError!bool,
        save: *const fn (context: *anyopaque, account: *const AccountKey, kind: CredentialKind, credential: *const Credential) SaveError!void,
        remove: *const fn (context: *anyopaque, account: *const AccountKey, kind: CredentialKind) RemoveError!void,
    };

    pub fn load(self: CredentialStore, account: *const AccountKey, kind: CredentialKind, out: *Credential) LoadError!void {
        return self.vtable.load(self.context, account, kind, out);
    }

    pub fn contains(self: CredentialStore, account: *const AccountKey, kind: CredentialKind) LoadError!bool {
        return self.vtable.contains(self.context, account, kind);
    }

    pub fn save(self: CredentialStore, account: *const AccountKey, kind: CredentialKind, credential: *const Credential) SaveError!void {
        return self.vtable.save(self.context, account, kind, credential);
    }

    pub fn remove(self: CredentialStore, account: *const AccountKey, kind: CredentialKind) RemoveError!void {
        return self.vtable.remove(self.context, account, kind);
    }
};

pub const MemoryStore = struct {
    pub const capacity: usize = 8;
    pub const max_recorded_operations: usize = 32;

    pub const Action = enum { load, contains, save, remove };
    pub const Operation = struct { action: Action, kind: CredentialKind };

    const Entry = struct {
        occupied: bool = false,
        account: AccountKey = .{},
        kind: CredentialKind = .access_token,
        credential: Credential = .empty,
    };

    entries: [capacity]Entry = @splat(.{}),
    operations: [max_recorded_operations]Operation = @splat(.{ .action = .load, .kind = .access_token }),
    operation_count: usize = 0,

    fail_next_load: ?LoadError = null,
    fail_loads_for: ?CredentialKind = null,
    fail_next_save: ?SaveError = null,
    fail_saves_for: ?CredentialKind = null,
    fail_next_remove: ?RemoveError = null,
    fail_removes_for: ?CredentialKind = null,

    const vtable: CredentialStore.VTable = .{
        .load = load,
        .contains = contains,
        .save = save,
        .remove = remove,
    };

    pub fn store(self: *MemoryStore) CredentialStore {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn deinit(self: *MemoryStore) void {
        for (&self.entries) |*entry| entry.credential.wipe();
        self.* = .{};
    }

    pub fn recordedOperations(self: *const MemoryStore) []const Operation {
        return self.operations[0..self.operation_count];
    }

    pub fn resetOperations(self: *MemoryStore) void {
        self.operation_count = 0;
    }

    fn record(self: *MemoryStore, action: Action, kind: CredentialKind) void {
        if (self.operation_count == max_recorded_operations) return;
        self.operations[self.operation_count] = .{ .action = action, .kind = kind };
        self.operation_count += 1;
    }

    fn find(self: *MemoryStore, account: *const AccountKey, kind: CredentialKind) ?*Entry {
        for (&self.entries) |*entry| {
            if (entry.occupied and entry.kind == kind and entry.account.eql(account)) return entry;
        }
        return null;
    }

    fn load(context: *anyopaque, account: *const AccountKey, kind: CredentialKind, out: *Credential) LoadError!void {
        const self: *MemoryStore = @ptrCast(@alignCast(context));
        self.record(.load, kind);
        if (self.fail_loads_for) |slot| {
            if (slot == kind) return self.fail_next_load orelse error.Unavailable;
        } else if (self.fail_next_load) |failure| {
            self.fail_next_load = null;
            return failure;
        }
        const entry = self.find(account, kind) orelse return error.NotFound;
        out.copyFrom(&entry.credential);
    }

    fn contains(context: *anyopaque, account: *const AccountKey, kind: CredentialKind) LoadError!bool {
        const self: *MemoryStore = @ptrCast(@alignCast(context));
        self.record(.contains, kind);
        if (self.fail_loads_for) |slot| {
            if (slot == kind) return self.fail_next_load orelse error.Unavailable;
        }
        return self.find(account, kind) != null;
    }

    fn save(context: *anyopaque, account: *const AccountKey, kind: CredentialKind, credential: *const Credential) SaveError!void {
        const self: *MemoryStore = @ptrCast(@alignCast(context));
        self.record(.save, kind);
        if (self.fail_saves_for) |slot| {
            if (slot == kind) return self.fail_next_save orelse error.Unavailable;
        } else if (self.fail_next_save) |failure| {
            self.fail_next_save = null;
            return failure;
        }
        if (self.find(account, kind)) |entry| {
            entry.credential.copyFrom(credential);
            return;
        }
        for (&self.entries) |*entry| {
            if (entry.occupied) continue;
            entry.* = .{ .occupied = true, .account = account.*, .kind = kind, .credential = credential.* };
            return;
        }
        return error.StoreFull;
    }

    fn remove(context: *anyopaque, account: *const AccountKey, kind: CredentialKind) RemoveError!void {
        const self: *MemoryStore = @ptrCast(@alignCast(context));
        self.record(.remove, kind);
        if (self.fail_removes_for) |slot| {
            if (slot == kind) return self.fail_next_remove orelse error.Unavailable;
        } else if (self.fail_next_remove) |failure| {
            self.fail_next_remove = null;
            return failure;
        }

        if (self.find(account, kind)) |entry| {
            entry.credential.wipe();
            entry.* = .{};
        }
    }
};

const macos_adapter = @import("keychain_macos.zig").Module(
    AccountKey,
    CredentialKind,
    Credential,
    LoadError,
    SaveError,
    RemoveError,
    CredentialStore,
    max_account_label_bytes,
    max_credential_bytes,
    accountLabel,
);

pub const ItemClass = macos_adapter.ItemClass;
pub const Accessibility = macos_adapter.Accessibility;
pub const AuthenticationUI = macos_adapter.AuthenticationUI;
pub const ItemQuery = macos_adapter.ItemQuery;
pub const macos = macos_adapter.macos;
