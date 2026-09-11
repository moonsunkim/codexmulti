const std = @import("std");
const domain = @import("domain.zig");
const keychain = @import("keychain.zig");
const runtime_paths = @import("runtime_paths.zig");

pub const current_schema_version: u16 = 1;

pub const max_accounts: usize = 16;
pub const max_id_bytes: usize = 48;
pub const max_label_bytes: usize = 64;
pub const max_email_bytes: usize = 254;
pub const max_plan_label_bytes: usize = 64;
pub const max_storage_key_bytes: usize = runtime_paths.max_segment_bytes;

pub const max_provider_key_bytes: usize = 96;

pub const max_text_bytes: usize =
    max_accounts * (max_id_bytes + max_label_bytes + max_storage_key_bytes +
        max_provider_key_bytes + max_email_bytes + max_plan_label_bytes);

comptime {
    if (max_storage_key_bytes > keychain.max_account_key_bytes) {
        @compileError("a storage key must fit a keychain account key");
    }
}

pub const AuthState = enum {
    connected,

    reauth_required,

    unavailable,
};

pub const Account = struct {
    id: []const u8,
    provider: domain.Provider,
    label: []const u8,

    label_is_custom: bool = false,
    provider_email: ?[]const u8 = null,
    plan_label: ?[]const u8 = null,

    storage_key: []const u8,
    provider_account_key: ?[]const u8 = null,
    auth_state: AuthState = .unavailable,

    auth_revision: u64 = 0,

    access_expires_at_unix_s: ?i64 = null,
    created_at_unix_s: i64,
    enabled: bool = true,

    pub fn profile(self: Account) domain.AccountProfile {
        return .{
            .id = self.id,
            .provider = self.provider,
            .display_name = self.label,
            .storage_key = self.storage_key,
            .enabled = self.enabled,
        };
    }

    pub fn accountKey(self: Account) keychain.AccountKeyError!keychain.AccountKey {
        return keychain.AccountKey.init(self.storage_key);
    }

    pub fn isRefreshable(self: Account) bool {
        return self.enabled and self.auth_state != .reauth_required;
    }
};

pub const Draft = struct {
    id: []const u8,
    provider: domain.Provider,
    label: []const u8,
    label_is_custom: bool = true,
    provider_email: ?[]const u8 = null,
    plan_label: ?[]const u8 = null,
    storage_key: []const u8,
    provider_account_key: ?[]const u8 = null,
    access_expires_at_unix_s: ?i64 = null,
    created_at_unix_s: i64,
    enabled: bool = true,
};

pub const ValidationError = error{
    InvalidId,
    InvalidLabel,

    InvalidStorageKey,
    InvalidProviderKey,
    InvalidEmail,
    InvalidPlanLabel,
};

pub const ProviderMetadata = struct {
    email: ?[]const u8 = null,
    email_observed: bool = false,
    plan_label: ?[]const u8 = null,
    plan_observed: bool = false,

    pub fn hasObservation(self: ProviderMetadata) bool {
        return self.email_observed or self.plan_observed;
    }
};

pub const AddError = ValidationError || error{
    RegistryFull,
    TextStorageFull,
    DuplicateId,

    DuplicateStorageKey,

    DuplicateProviderIdentity,
};

pub const LookupError = error{UnknownAccount};

pub const DocumentError = error{
    UnsupportedSchemaVersion,
    TooManyAccounts,
};

pub const LoadError = AddError || DocumentError;

pub const RegistryDocument = struct {
    schema_version: u16 = current_schema_version,
    accounts: []const Account = &.{},
};

pub fn validateDocument(document: RegistryDocument) LoadError!void {
    if (document.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
    if (document.accounts.len > max_accounts) return error.TooManyAccounts;
    for (document.accounts, 0..) |account, index| {
        try validateId(account.id);
        try validateLabel(account.label);
        if (account.provider_email) |email| try validateEmail(email);
        if (account.plan_label) |plan| try validatePlanLabel(plan);
        try validateStorageKey(account.storage_key);
        if (account.provider_account_key) |key| try validateProviderKey(key);
        for (document.accounts[index + 1 ..]) |other| {
            if (std.mem.eql(u8, account.id, other.id)) return error.DuplicateId;
            if (runtime_paths.segmentsCollide(account.storage_key, other.storage_key)) {
                return error.DuplicateStorageKey;
            }
            if (account.provider != other.provider) continue;
            if (optionalTextEqual(account.provider_account_key, other.provider_account_key)) {
                return error.DuplicateProviderIdentity;
            }
        }
    }
}

pub fn validateId(id: []const u8) ValidationError!void {
    if (id.len == 0 or id.len > max_id_bytes) return error.InvalidId;
    for (id) |byte| {
        switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => {},
            else => return error.InvalidId,
        }
    }
}

pub fn validateLabel(label: []const u8) ValidationError!void {
    if (label.len == 0 or label.len > max_label_bytes) return error.InvalidLabel;
    if (label[0] == ' ' or label[label.len - 1] == ' ') return error.InvalidLabel;
    for (label) |byte| {
        if (byte < 0x20 or byte == 0x7f) return error.InvalidLabel;
    }
    if (!std.unicode.utf8ValidateSlice(label)) return error.InvalidLabel;
}

pub fn validateStorageKey(storage_key: []const u8) ValidationError!void {
    if (storage_key.len > max_storage_key_bytes) return error.InvalidStorageKey;
    runtime_paths.validateAccountSegment(storage_key) catch return error.InvalidStorageKey;
    _ = keychain.AccountKey.init(storage_key) catch return error.InvalidStorageKey;
}

pub fn validateProviderKey(provider_account_key: []const u8) ValidationError!void {
    if (provider_account_key.len == 0 or provider_account_key.len > max_provider_key_bytes) {
        return error.InvalidProviderKey;
    }
    for (provider_account_key) |byte| {
        if (byte < 0x20 or byte > 0x7e) return error.InvalidProviderKey;
    }
}

pub fn validateEmail(email: []const u8) ValidationError!void {
    if (email.len == 0 or email.len > max_email_bytes) return error.InvalidEmail;
    var at_count: usize = 0;
    for (email) |byte| {
        if (byte < 0x21 or byte > 0x7e) return error.InvalidEmail;
        if (byte == '@') at_count += 1;
    }
    if (at_count != 1 or email[0] == '@' or email[email.len - 1] == '@') return error.InvalidEmail;
}

pub fn validatePlanLabel(plan: []const u8) ValidationError!void {
    if (plan.len == 0 or plan.len > max_plan_label_bytes) return error.InvalidPlanLabel;
    for (plan) |byte| {
        if (byte < 0x20 or byte == 0x7f) return error.InvalidPlanLabel;
    }
    if (!std.unicode.utf8ValidateSlice(plan)) return error.InvalidPlanLabel;
}

const Span = struct {
    start: u32 = 0,
    len: u32 = 0,
};

const Entry = struct {
    id: Span = .{},
    label: Span = .{},
    label_is_custom: bool = false,
    provider_email: ?Span = null,
    plan_label: ?Span = null,
    storage_key: Span = .{},
    provider_account_key: ?Span = null,
    provider: domain.Provider = .codex,
    auth_state: AuthState = .unavailable,
    auth_revision: u64 = 0,
    access_expires_at_unix_s: ?i64 = null,
    created_at_unix_s: i64 = 0,
    enabled: bool = true,
};

pub const Registry = struct {
    text: [max_text_bytes]u8 = @splat(0),
    text_len: u32 = 0,
    entries: [max_accounts]Entry = @splat(.{}),
    count: usize = 0,

    revision: u64 = 0,

    pub fn clear(self: *Registry) void {
        const revision = self.revision;
        self.* = .{};
        self.revision = revision +% 1;
    }

    pub fn accountCount(self: *const Registry) usize {
        return self.count;
    }

    pub fn at(self: *const Registry, index: usize) ?Account {
        if (index >= self.count) return null;
        return self.resolve(index);
    }

    pub fn indexOf(self: *const Registry, id: []const u8) ?usize {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (std.mem.eql(u8, self.textOf(self.entries[index].id), id)) return index;
        }
        return null;
    }

    pub fn get(self: *const Registry, id: []const u8) ?Account {
        return self.at(self.indexOf(id) orelse return null);
    }

    pub fn indexOfStorageKey(self: *const Registry, storage_key: []const u8) ?usize {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (runtime_paths.segmentsCollide(self.textOf(self.entries[index].storage_key), storage_key)) {
                return index;
            }
        }
        return null;
    }

    pub fn indexOfProviderIdentity(
        self: *const Registry,
        provider: domain.Provider,
        provider_account_key: []const u8,
    ) ?usize {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const entry = self.entries[index];
            if (entry.provider != provider) continue;
            const span = entry.provider_account_key orelse continue;
            if (std.mem.eql(u8, self.textOf(span), provider_account_key)) return index;
        }
        return null;
    }

    pub fn add(self: *Registry, draft: Draft) AddError!usize {
        try validateId(draft.id);
        try validateLabel(draft.label);
        if (draft.provider_email) |email| try validateEmail(email);
        if (draft.plan_label) |plan| try validatePlanLabel(plan);
        try validateStorageKey(draft.storage_key);
        if (draft.provider_account_key) |key| try validateProviderKey(key);

        if (self.count == max_accounts) return error.RegistryFull;
        if (self.indexOf(draft.id) != null) return error.DuplicateId;
        if (self.indexOfStorageKey(draft.storage_key) != null) return error.DuplicateStorageKey;
        if (draft.provider_account_key) |key| {
            if (self.indexOfProviderIdentity(draft.provider, key) != null) {
                return error.DuplicateProviderIdentity;
            }
        }

        return self.appendResolved(.{
            .id = draft.id,
            .provider = draft.provider,
            .label = draft.label,
            .label_is_custom = draft.label_is_custom,
            .provider_email = draft.provider_email,
            .plan_label = draft.plan_label,
            .storage_key = draft.storage_key,
            .provider_account_key = draft.provider_account_key,
            .auth_state = .unavailable,
            .auth_revision = 0,
            .access_expires_at_unix_s = draft.access_expires_at_unix_s,
            .created_at_unix_s = draft.created_at_unix_s,
            .enabled = draft.enabled,
        });
    }

    pub fn setLabel(self: *Registry, id: []const u8, label: []const u8) (LookupError || ValidationError || error{TextStorageFull})!void {
        try validateLabel(label);
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        const span = self.intern(label) orelse return error.TextStorageFull;
        self.entries[index].label = span;
        self.entries[index].label_is_custom = true;
        self.revision +%= 1;
    }

    pub fn setProviderMetadata(
        self: *Registry,
        id: []const u8,
        metadata: ProviderMetadata,
    ) (LookupError || ValidationError || error{TextStorageFull})!void {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        const entry = &self.entries[index];
        var changed = false;

        if (metadata.email_observed) {
            const next_email: ?Span = if (metadata.email) |email| blk: {
                try validateEmail(email);
                if (entry.provider_email) |existing| {
                    if (std.mem.eql(u8, self.textOf(existing), email)) break :blk existing;
                }
                changed = true;
                break :blk self.intern(email) orelse return error.TextStorageFull;
            } else blk: {
                if (entry.provider_email != null) changed = true;
                break :blk null;
            };
            entry.provider_email = next_email;

            if (!entry.label_is_custom) {
                const next_label = if (next_email) |span| span else blk: {
                    const fallback = defaultLabel(entry.provider);
                    if (std.mem.eql(u8, self.textOf(entry.label), fallback)) break :blk entry.label;
                    break :blk self.intern(fallback) orelse return error.TextStorageFull;
                };
                if (!std.mem.eql(u8, self.textOf(entry.label), self.textOf(next_label))) changed = true;
                entry.label = next_label;
            }
        }

        if (metadata.plan_observed) {
            const next_plan: ?Span = if (metadata.plan_label) |plan| blk: {
                try validatePlanLabel(plan);
                if (entry.plan_label) |existing| {
                    if (std.mem.eql(u8, self.textOf(existing), plan)) break :blk existing;
                }
                changed = true;
                break :blk self.intern(plan) orelse return error.TextStorageFull;
            } else blk: {
                if (entry.plan_label != null) changed = true;
                break :blk null;
            };
            entry.plan_label = next_plan;
        }

        if (changed) self.revision +%= 1;
    }

    pub fn setEnabled(self: *Registry, id: []const u8, enabled: bool) LookupError!void {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        if (self.entries[index].enabled == enabled) return;
        self.entries[index].enabled = enabled;
        self.revision +%= 1;
    }

    pub fn setProviderIdentity(
        self: *Registry,
        id: []const u8,
        provider_account_key: ?[]const u8,
    ) (LookupError || ValidationError || error{ TextStorageFull, DuplicateProviderIdentity })!u64 {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        const entry = &self.entries[index];
        if (provider_account_key) |key| {
            try validateProviderKey(key);
            if (self.indexOfProviderIdentity(entry.provider, key)) |owner| {
                if (owner != index) return error.DuplicateProviderIdentity;
            }
            if (entry.provider_account_key) |existing| {
                if (std.mem.eql(u8, self.textOf(existing), key)) return entry.auth_revision;
            }
            const span = self.intern(key) orelse return error.TextStorageFull;
            self.entries[index].provider_account_key = span;
        } else {
            if (entry.provider_account_key == null) return entry.auth_revision;
            self.entries[index].provider_account_key = null;
        }
        self.entries[index].auth_revision +%= 1;
        self.revision +%= 1;
        return self.entries[index].auth_revision;
    }

    pub fn markConnected(
        self: *Registry,
        id: []const u8,
        provider_account_key: ?[]const u8,
    ) (LookupError || ValidationError || error{ TextStorageFull, DuplicateProviderIdentity })!u64 {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        if (provider_account_key) |key| {
            try validateProviderKey(key);
            if (self.indexOfProviderIdentity(self.entries[index].provider, key)) |owner| {
                if (owner != index) return error.DuplicateProviderIdentity;
            }
            const span = self.intern(key) orelse return error.TextStorageFull;
            self.entries[index].provider_account_key = span;
        }
        self.entries[index].auth_state = .connected;
        self.entries[index].auth_revision +%= 1;
        self.revision +%= 1;
        return self.entries[index].auth_revision;
    }

    pub fn markAuthState(self: *Registry, id: []const u8, state: AuthState) LookupError!u64 {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        if (self.entries[index].auth_state == state) return self.entries[index].auth_revision;
        self.entries[index].auth_state = state;
        if (state == .reauth_required) self.entries[index].auth_revision +%= 1;
        self.revision +%= 1;
        return self.entries[index].auth_revision;
    }

    pub fn markCredentialsRemoved(self: *Registry, id: []const u8) LookupError!u64 {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        self.entries[index].auth_state = .reauth_required;
        self.entries[index].auth_revision +%= 1;
        self.revision +%= 1;
        return self.entries[index].auth_revision;
    }

    pub fn setAccessExpiry(self: *Registry, id: []const u8, expires_at_unix_s: ?i64) LookupError!void {
        const index = self.indexOf(id) orelse return error.UnknownAccount;
        if (self.entries[index].access_expires_at_unix_s == expires_at_unix_s) return;
        self.entries[index].access_expires_at_unix_s = expires_at_unix_s;
        self.revision +%= 1;
    }

    pub fn move(self: *Registry, id: []const u8, new_index: usize) LookupError!void {
        const from = self.indexOf(id) orelse return error.UnknownAccount;
        if (self.count == 0) return error.UnknownAccount;
        const to = @min(new_index, self.count - 1);
        if (from == to) return;
        const moved = self.entries[from];
        if (from < to) {
            var index = from;
            while (index < to) : (index += 1) self.entries[index] = self.entries[index + 1];
        } else {
            var index = from;
            while (index > to) : (index -= 1) self.entries[index] = self.entries[index - 1];
        }
        self.entries[to] = moved;
        self.revision +%= 1;
    }

    pub fn remove(self: *Registry, id: []const u8) LookupError!void {
        const target = self.indexOf(id) orelse return error.UnknownAccount;

        var rebuilt: Registry = .{};
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (index == target) continue;

            _ = rebuilt.appendResolved(self.resolve(index)) catch unreachable;
        }
        rebuilt.revision = self.revision +% 1;
        self.* = rebuilt;
    }

    pub fn loadDocument(self: *Registry, document: RegistryDocument) LoadError!void {
        try validateDocument(document);
        var rebuilt: Registry = .{};
        for (document.accounts) |account| {
            var migrated = account;

            if (!migrated.label_is_custom and migrated.provider_email == null and
                !std.mem.eql(u8, migrated.label, defaultLabel(migrated.provider)))
            {
                migrated.label_is_custom = true;
            }
            _ = try rebuilt.appendResolved(migrated);
        }
        rebuilt.revision = self.revision +% 1;
        self.* = rebuilt;
    }

    pub fn toDocument(self: *const Registry, out: []Account) error{BufferTooSmall}!RegistryDocument {
        if (out.len < self.count) return error.BufferTooSmall;
        var index: usize = 0;
        while (index < self.count) : (index += 1) out[index] = self.resolve(index);
        return .{ .accounts = out[0..self.count] };
    }

    fn resolve(self: *const Registry, index: usize) Account {
        const entry = self.entries[index];
        return .{
            .id = self.textOf(entry.id),
            .provider = entry.provider,
            .label = self.textOf(entry.label),
            .label_is_custom = entry.label_is_custom,
            .provider_email = if (entry.provider_email) |span| self.textOf(span) else null,
            .plan_label = if (entry.plan_label) |span| self.textOf(span) else null,
            .storage_key = self.textOf(entry.storage_key),
            .provider_account_key = if (entry.provider_account_key) |span| self.textOf(span) else null,
            .auth_state = entry.auth_state,
            .auth_revision = entry.auth_revision,
            .access_expires_at_unix_s = entry.access_expires_at_unix_s,
            .created_at_unix_s = entry.created_at_unix_s,
            .enabled = entry.enabled,
        };
    }

    fn textOf(self: *const Registry, span: Span) []const u8 {
        return self.text[span.start..][0..span.len];
    }

    fn intern(self: *Registry, text: []const u8) ?Span {
        if (text.len > max_text_bytes - self.text_len) return null;
        const start = self.text_len;
        @memcpy(self.text[start..][0..text.len], text);
        self.text_len += @intCast(text.len);
        return .{ .start = start, .len = @intCast(text.len) };
    }

    fn appendResolved(self: *Registry, account: Account) error{ RegistryFull, TextStorageFull }!usize {
        if (self.count == max_accounts) return error.RegistryFull;
        const id = self.intern(account.id) orelse return error.TextStorageFull;
        const label = self.intern(account.label) orelse return error.TextStorageFull;
        const email: ?Span = if (account.provider_email) |value|
            self.intern(value) orelse return error.TextStorageFull
        else
            null;
        const plan: ?Span = if (account.plan_label) |value|
            self.intern(value) orelse return error.TextStorageFull
        else
            null;
        const storage_key = self.intern(account.storage_key) orelse return error.TextStorageFull;
        const provider_key: ?Span = if (account.provider_account_key) |key|
            self.intern(key) orelse return error.TextStorageFull
        else
            null;

        const index = self.count;
        self.entries[index] = .{
            .id = id,
            .label = label,
            .label_is_custom = account.label_is_custom,
            .provider_email = email,
            .plan_label = plan,
            .storage_key = storage_key,
            .provider_account_key = provider_key,
            .provider = account.provider,
            .auth_state = account.auth_state,
            .auth_revision = account.auth_revision,
            .access_expires_at_unix_s = account.access_expires_at_unix_s,
            .created_at_unix_s = account.created_at_unix_s,
            .enabled = account.enabled,
        };
        self.count += 1;
        self.revision +%= 1;
        return index;
    }
};

pub fn defaultLabel(provider: domain.Provider) []const u8 {
    return switch (provider) {
        .codex => "Codex account",
        .claude => "Unsupported account",
    };
}

fn optionalTextEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}
