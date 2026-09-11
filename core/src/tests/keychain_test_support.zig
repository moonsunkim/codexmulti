const std = @import("std");
const keychain = @import("../keychain.zig");

const max_account_label_bytes = keychain.max_account_label_bytes;
const Credential = keychain.Credential;
const CredentialStore = keychain.CredentialStore;
const ItemClass = keychain.ItemClass;
const Accessibility = keychain.Accessibility;
const AuthenticationUI = keychain.AuthenticationUI;
const ItemQuery = keychain.ItemQuery;
const macos = keychain.macos;

pub const RecordedItem = struct {
    service_bytes: [128]u8 = @splat(0),
    service_len: u8 = 0,
    account_bytes: [max_account_label_bytes]u8 = @splat(0),
    account_len: u8 = 0,
    class: ItemClass = .generic_password,
    accessibility: Accessibility = .when_unlocked_this_device_only,
    synchronizable: bool = false,
    authentication_ui: AuthenticationUI = .fail,

    fn init(query: ItemQuery) RecordedItem {
        var recorded: RecordedItem = .{
            .class = query.class,
            .accessibility = query.accessibility,
            .synchronizable = query.synchronizable,
            .authentication_ui = query.authentication_ui,
        };
        @memcpy(recorded.service_bytes[0..query.service.len], query.service);
        recorded.service_len = @intCast(query.service.len);
        @memcpy(recorded.account_bytes[0..query.account.len], query.account);
        recorded.account_len = @intCast(query.account.len);
        return recorded;
    }

    pub fn serviceText(self: *const RecordedItem) []const u8 {
        return self.service_bytes[0..self.service_len];
    }

    pub fn accountText(self: *const RecordedItem) []const u8 {
        return self.account_bytes[0..self.account_len];
    }

    fn sameItem(self: *const RecordedItem, other: *const RecordedItem) bool {
        return std.mem.eql(u8, self.serviceText(), other.serviceText()) and
            std.mem.eql(u8, self.accountText(), other.accountText());
    }
};

pub const FakeSecItem = struct {
    const capacity: usize = 8;
    const max_calls: usize = 32;

    pub const Call = enum { copy, matches, add, update, delete };

    const Entry = struct {
        occupied: bool = false,
        item: RecordedItem = .{},
        credential: Credential = .empty,
    };

    entries: [capacity]Entry = @splat(.{}),
    calls: [max_calls]Call = @splat(.copy),
    items: [max_calls]RecordedItem = @splat(.{}),
    call_count: usize = 0,

    fail_call: ?Call = null,
    fail_status: macos.OSStatus = macos.status_io,

    duplicate_adds: u8 = 0,

    const vtable: macos.SecItemApi.VTable = .{
        .copy = copy,
        .matches = matches,
        .add = add,
        .update = update,
        .delete = delete,
    };

    pub fn api(self: *FakeSecItem) macos.SecItemApi {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn deinit(self: *FakeSecItem) void {
        for (&self.entries) |*entry| entry.credential.wipe();
        self.* = .{};
    }

    pub fn recordedCalls(self: *const FakeSecItem) []const Call {
        return self.calls[0..self.call_count];
    }

    pub fn recordedItems(self: *const FakeSecItem) []const RecordedItem {
        return self.items[0..self.call_count];
    }

    pub fn resetCalls(self: *FakeSecItem) void {
        self.call_count = 0;
    }

    fn record(self: *FakeSecItem, call: Call, query: ItemQuery) ?macos.OSStatus {
        if (self.call_count < max_calls) {
            self.calls[self.call_count] = call;
            self.items[self.call_count] = .init(query);
            self.call_count += 1;
        }
        if (self.fail_call) |failing| {
            if (failing == call) return self.fail_status;
        }
        return null;
    }

    fn find(self: *FakeSecItem, query: ItemQuery) ?*Entry {
        const wanted: RecordedItem = .init(query);
        for (&self.entries) |*entry| {
            if (entry.occupied and entry.item.sameItem(&wanted)) return entry;
        }
        return null;
    }

    fn copy(context: *anyopaque, query: ItemQuery, out: *Credential) macos.OSStatus {
        const self: *FakeSecItem = @ptrCast(@alignCast(context));
        if (self.record(.copy, query)) |status| return status;
        const entry = self.find(query) orelse return macos.status_item_not_found;
        out.copyFrom(&entry.credential);
        return macos.status_success;
    }

    fn matches(context: *anyopaque, query: ItemQuery) macos.OSStatus {
        const self: *FakeSecItem = @ptrCast(@alignCast(context));
        if (self.record(.matches, query)) |status| return status;
        return if (self.find(query) != null) macos.status_success else macos.status_item_not_found;
    }

    pub fn add(context: *anyopaque, query: ItemQuery, credential: *const Credential) macos.OSStatus {
        const self: *FakeSecItem = @ptrCast(@alignCast(context));
        if (self.record(.add, query)) |status| return status;
        if (self.duplicate_adds > 0) {
            self.duplicate_adds -= 1;

            if (self.find(query) == null) {
                for (&self.entries) |*entry| {
                    if (entry.occupied) continue;
                    entry.* = .{ .occupied = true, .item = .init(query), .credential = .empty };
                    break;
                }
            }
            return macos.status_duplicate_item;
        }
        if (self.find(query) != null) return macos.status_duplicate_item;
        for (&self.entries) |*entry| {
            if (entry.occupied) continue;
            entry.* = .{ .occupied = true, .item = .init(query), .credential = credential.* };
            return macos.status_success;
        }
        return macos.status_disk_full;
    }

    fn update(context: *anyopaque, query: ItemQuery, credential: *const Credential) macos.OSStatus {
        const self: *FakeSecItem = @ptrCast(@alignCast(context));
        if (self.record(.update, query)) |status| return status;
        const entry = self.find(query) orelse return macos.status_item_not_found;
        entry.credential.copyFrom(credential);
        return macos.status_success;
    }

    fn delete(context: *anyopaque, query: ItemQuery) macos.OSStatus {
        const self: *FakeSecItem = @ptrCast(@alignCast(context));
        if (self.record(.delete, query)) |status| return status;
        const entry = self.find(query) orelse return macos.status_item_not_found;
        entry.credential.wipe();
        entry.* = .{};
        return macos.status_success;
    }
};

pub fn wiredKeychain(fake: *FakeSecItem, backend: *macos.SecItemStore, adapter: *macos.KeychainStore) !CredentialStore {
    backend.* = .init(fake.api());
    adapter.* = try macos.KeychainStore.init(macos.default_service);
    adapter.backend = backend.backend();
    return adapter.store();
}
