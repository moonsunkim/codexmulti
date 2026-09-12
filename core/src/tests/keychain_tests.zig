const std = @import("std");
const keychain = @import("../keychain.zig");
const test_support = @import("keychain_test_support.zig");

const max_account_key_bytes = keychain.max_account_key_bytes;
const max_account_label_bytes = keychain.max_account_label_bytes;
const max_credential_bytes = keychain.max_credential_bytes;
const AccountKey = keychain.AccountKey;
const CredentialKind = keychain.CredentialKind;
const accountLabel = keychain.accountLabel;
const Credential = keychain.Credential;
const LoadError = keychain.LoadError;
const SaveError = keychain.SaveError;
const RemoveError = keychain.RemoveError;
const CredentialStore = keychain.CredentialStore;
const MemoryStore = keychain.MemoryStore;
const ItemClass = keychain.ItemClass;
const Accessibility = keychain.Accessibility;
const AuthenticationUI = keychain.AuthenticationUI;
const ItemQuery = keychain.ItemQuery;
const macos = keychain.macos;
const FakeSecItem = test_support.FakeSecItem;
const wiredKeychain = test_support.wiredKeychain;

const testing = std.testing;

const demo_secret = "demo-not-a-real-secret-0000";
const other_secret = "demo-not-a-real-secret-1111";

fn demoKey() AccountKey {
    return AccountKey.init("claude-demo") catch unreachable;
}

test "account key accepts app storage keys and rejects path-like or oversized input" {
    const key = try AccountKey.fromProfile(.{
        .id = "acct-claude-demo",
        .provider = .claude,
        .display_name = "Claude Demo",
        .storage_key = "claude-demo",
    });
    try testing.expectEqualStrings("claude-demo", key.slice());

    try testing.expectError(error.EmptyAccountKey, AccountKey.init(""));
    try testing.expectError(error.AccountKeyTooLong, AccountKey.init("k" ** (max_account_key_bytes + 1)));
    try testing.expectError(error.InvalidAccountKey, AccountKey.init("../escape"));
    try testing.expectError(error.InvalidAccountKey, AccountKey.init("claude/demo"));
    try testing.expectError(error.InvalidAccountKey, AccountKey.init("claude demo"));
    try testing.expectError(error.InvalidAccountKey, AccountKey.init("claude\ndemo"));
    try testing.expectError(error.InvalidAccountKey, AccountKey.init(".hidden"));

    const same = try AccountKey.init("claude-demo");
    const other = try AccountKey.init("codex-demo");
    try testing.expect(key.eql(&same));
    try testing.expect(!key.eql(&other));
}

test "account label is namespaced per account and slot" {
    const key = demoKey();
    var buffer: [max_account_label_bytes]u8 = undefined;
    try testing.expectEqualStrings("claude-demo.access", try accountLabel(&key, .access_token, &buffer));
    try testing.expectEqualStrings("claude-demo.refresh", try accountLabel(&key, .refresh_token, &buffer));
    try testing.expectEqualStrings("claude-demo.refresh-staged", try accountLabel(&key, .staged_refresh_token, &buffer));
    try testing.expectEqualStrings("claude-demo.codex-auth", try accountLabel(&key, .codex_auth_backup, &buffer));

    var tiny: [4]u8 = undefined;
    try testing.expectError(error.BufferTooSmall, accountLabel(&key, .access_token, &tiny));
}

test "credential redacts itself in logs and documents" {
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();

    var text: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&text);
    try writer.print("saving {f} for {f}", .{ &credential, demoKey() });
    try testing.expectEqualStrings("saving [redacted credential] for claude-demo", writer.buffered());

    var json: std.Io.Writer.Allocating = .init(testing.allocator);
    defer json.deinit();
    try std.json.Stringify.value(
        .{ .account = "claude-demo", .credential = credential },
        .{},
        &json.writer,
    );
    const encoded = json.written();
    try testing.expect(std.mem.indexOf(u8, encoded, "[redacted]") != null);
    try testing.expect(std.mem.indexOf(u8, encoded, demo_secret) == null);
}

test "credential memory holds no plaintext and wipe clears it" {
    var credential = try Credential.init(demo_secret);

    try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&credential), demo_secret) == null);
    try testing.expect(credential.eqlPlaintext(demo_secret));
    try testing.expectEqual(@as(usize, demo_secret.len), credential.length());

    var out: [max_credential_bytes]u8 = undefined;
    const plaintext = try credential.copyPlaintext(&out);
    try testing.expectEqualStrings(demo_secret, plaintext);
    std.crypto.secureZero(u8, plaintext);
    var tiny: [4]u8 = undefined;
    try testing.expectError(error.BufferTooSmall, credential.copyPlaintext(&tiny));

    credential.wipe();
    try testing.expect(credential.isEmpty());
    try testing.expect(std.mem.allEqual(u8, credential.masked[0..], 0));
    try testing.expect(std.mem.allEqual(u8, credential.mask[0..], 0));
    try testing.expect(!credential.eqlPlaintext(demo_secret));

    try testing.expectError(error.SecretTooLong, credential.set("s" ** (max_credential_bytes + 1)));
}

test "credential equality is content exact across independent masks" {
    var first = try Credential.init(demo_secret);
    defer first.wipe();
    var second = try Credential.init(demo_secret);
    defer second.wipe();
    var third = try Credential.init(other_secret);
    defer third.wipe();

    try testing.expect(!std.mem.eql(u8, &first.masked, &second.masked));
    try testing.expect(first.eql(&second));
    try testing.expect(!first.eql(&third));

    var streamed: Credential = .empty;
    defer streamed.wipe();
    streamed.reset();
    try streamed.append(demo_secret[0..7]);
    try streamed.append(demo_secret[7..]);
    try testing.expect(streamed.eql(&first));
}

test "memory store keeps slots separate, is idempotent, and injects faults deterministically" {
    var fake: MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const key = demoKey();
    const other_key = try AccountKey.init("codex-demo");

    var access = try Credential.init(demo_secret);
    defer access.wipe();
    var refresh = try Credential.init(other_secret);
    defer refresh.wipe();

    var loaded: Credential = .empty;
    defer loaded.wipe();
    try testing.expectError(error.NotFound, store.load(&key, .access_token, &loaded));
    try testing.expect(!try store.contains(&key, .access_token));

    try store.save(&key, .access_token, &access);
    try store.save(&key, .refresh_token, &refresh);
    try testing.expect(try store.contains(&key, .access_token));
    try store.load(&key, .access_token, &loaded);
    try testing.expect(loaded.eql(&access));
    try store.load(&key, .refresh_token, &loaded);
    try testing.expect(loaded.eql(&refresh));

    try testing.expect(!try store.contains(&other_key, .access_token));

    try store.save(&key, .access_token, &refresh);
    try store.load(&key, .access_token, &loaded);
    try testing.expect(loaded.eql(&refresh));
    try store.remove(&key, .access_token);
    try store.remove(&key, .access_token);
    try testing.expectError(error.NotFound, store.load(&key, .access_token, &loaded));

    fake.fail_saves_for = .staged_refresh_token;
    fake.fail_next_save = error.AccessDenied;
    try testing.expectError(error.AccessDenied, store.save(&key, .staged_refresh_token, &refresh));
    try testing.expectError(error.AccessDenied, store.save(&key, .staged_refresh_token, &refresh));
    fake.fail_saves_for = null;
    fake.fail_next_save = error.Unavailable;
    try testing.expectError(error.Unavailable, store.save(&key, .access_token, &refresh));
    try store.save(&key, .access_token, &refresh);

    fake.resetOperations();
    try store.remove(&key, .refresh_token);
    try testing.expectEqual(@as(usize, 1), fake.recordedOperations().len);
    try testing.expectEqual(MemoryStore.Action.remove, fake.recordedOperations()[0].action);
}

test "memory store never keeps plaintext and wipes on deinit" {
    var fake: MemoryStore = .{};
    const store = fake.store();
    const key = demoKey();
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();

    try store.save(&key, .refresh_token, &credential);
    try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&fake), demo_secret) == null);

    fake.deinit();
    try testing.expectEqual(@as(usize, 0), fake.operation_count);
    try testing.expect(!try fake.store().contains(&key, .refresh_token));
}

test "memory store reports capacity exhaustion instead of dropping a credential" {
    var fake: MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();

    var filled: usize = 0;
    while (filled < MemoryStore.capacity) : (filled += 1) {
        var name_buffer: [16]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buffer, "acct-{d}", .{filled});
        const key = try AccountKey.init(name);
        try store.save(&key, .refresh_token, &credential);
    }
    const overflow_key = try AccountKey.init("acct-overflow");
    try testing.expectError(error.StoreFull, store.save(&overflow_key, .refresh_token, &credential));
}

test "macOS adapter fails closed until a SecItem backend is wired" {
    var adapter = try macos.KeychainStore.init(macos.default_service);
    try testing.expect(!adapter.isWired());
    const store = adapter.store();
    const key = demoKey();
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();
    var loaded: Credential = .empty;
    defer loaded.wipe();

    try testing.expectError(error.Unsupported, store.load(&key, .refresh_token, &loaded));
    try testing.expectError(error.Unsupported, store.contains(&key, .refresh_token));
    try testing.expectError(error.Unsupported, store.save(&key, .refresh_token, &credential));
    try testing.expectError(error.Unsupported, store.remove(&key, .refresh_token));

    try testing.expect(loaded.isEmpty());

    try testing.expectError(error.ForeignKeychainService, macos.KeychainStore.init("com.apple.Safari"));
    try testing.expectError(error.ForeignKeychainService, macos.KeychainStore.init("Chrome Safe Storage"));
}

test "macOS item queries stay inside this app's own generic-password namespace" {
    var adapter = try macos.KeychainStore.init(macos.v2_service);
    const key = demoKey();
    var buffer: [max_account_label_bytes]u8 = undefined;
    const item = try adapter.query(&key, .staged_refresh_token, &buffer);

    try testing.expect(item.isSelfOwned());
    try testing.expectEqual(ItemClass.generic_password, item.class);
    try testing.expect(!item.synchronizable);
    try testing.expectEqual(Accessibility.when_unlocked_this_device_only, item.accessibility);
    try testing.expectEqual(AuthenticationUI.fail, item.authentication_ui);
    try testing.expect(item.isWritableV2());
    try testing.expectEqualStrings("claude-demo.refresh-staged", item.account);

    var sign_in = try macos.KeychainStore.initForSignIn(macos.v2_service);
    var sign_in_buffer: [max_account_label_bytes]u8 = undefined;
    const sign_in_item = try sign_in.query(&key, .refresh_token, &sign_in_buffer);
    try testing.expectEqual(AuthenticationUI.allow, sign_in_item.authentication_ui);

    var legacy = try macos.KeychainStore.init(macos.legacy_service);
    var legacy_buffer: [max_account_label_bytes]u8 = undefined;
    const legacy_item = try legacy.query(&key, .refresh_token, &legacy_buffer);
    try testing.expect(legacy_item.isSelfOwned());
    try testing.expect(!legacy_item.isWritableV2());
    try testing.expectEqual(AuthenticationUI.fail, legacy_item.authentication_ui);

    try testing.expectError(
        error.ForeignKeychainService,
        macos.KeychainStore.init(macos.app_service_prefix ++ ".credentials"),
    );
    try testing.expectError(
        error.ForeignKeychainService,
        macos.KeychainStore.init(macos.app_service_prefix ++ ".preview"),
    );
    try testing.expectError(error.ForeignKeychainService, macos.KeychainStore.initForSignIn(macos.legacy_service));

    const foreign_service: ItemQuery = .{ .service = "com.google.Chrome", .account = item.account };
    try testing.expect(!foreign_service.isSelfOwned());
    const cookie_item: ItemQuery = .{ .class = .internet_password, .service = item.service, .account = item.account };
    try testing.expect(!cookie_item.isSelfOwned());
    const synced_item: ItemQuery = .{ .service = item.service, .account = item.account, .synchronizable = true };
    try testing.expect(!synced_item.isSelfOwned());
}

test "the Keychain policy module keeps its app-owned constants and no Claude Code capability" {
    const source = @embedFile("../keychain_macos.zig");
    for ([_][]const u8{
        "ClaudeCodeSecItemCapability",
        "isClaudeCodeItem",
        "claude_code_service",
        "claude_code_fallback_account",
        "isValidClaudeCodeAccount",
    }) |needle| {
        try testing.expect(std.mem.indexOf(u8, source, needle) == null);
    }

    try testing.expectEqualStrings("dev.codexmulti.app", macos.app_service_prefix);
    try testing.expectEqualStrings("dev.codexmulti.app", macos.legacy_service);
    try testing.expectEqualStrings("dev.codexmulti.app.v2", macos.v2_service);
    try testing.expectEqualStrings(
        "identifier \"dev.codexmulti.app\" and certificate root = H\"348b6cf6eed9f518a04c89f02cca7cd91674c55d\"",
        macos.local_designated_requirement,
    );

    const foreign: ItemQuery = .{ .service = "Claude Code-credentials-0123abcd", .account = "demo-user" };
    try testing.expect(!foreign.isSelfOwned());
    try testing.expect(std.mem.indexOf(u8, source, "fn systemCopy(_: *anyopaque, query: ItemQuery, out: *Credential) OSStatus {\n                if (!query.isSelfOwned()) return status_param;") != null);
}

test "wiring the SecItem backend performs no keychain I/O" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = undefined;
    var adapter: macos.KeychainStore = undefined;
    _ = try wiredKeychain(&fake, &backend, &adapter);

    try testing.expect(adapter.isWired());

    try testing.expectEqual(@as(usize, 0), fake.call_count);
}

test "versioned keychain reads v2 first, falls back passively, and writes only v2" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = .init(fake.api());
    const wired = backend.backend();

    var primary = try macos.KeychainStore.init(macos.v2_service);
    primary.backend = wired;
    var legacy = try macos.KeychainStore.init(macos.legacy_service);
    legacy.backend = wired;
    var versioned: macos.VersionedKeychainStore = .{
        .primary = primary.store(),
        .legacy = legacy.store(),
    };
    const store = versioned.store();

    const key = demoKey();
    var legacy_secret = try Credential.init(demo_secret);
    defer legacy_secret.wipe();
    var fresh_secret = try Credential.init(other_secret);
    defer fresh_secret.wipe();
    var loaded: Credential = .empty;
    defer loaded.wipe();

    var legacy_buffer: [max_account_label_bytes]u8 = undefined;
    const legacy_query = try legacy.query(&key, .refresh_token, &legacy_buffer);
    try testing.expectEqual(macos.status_success, FakeSecItem.add(&fake, legacy_query, &legacy_secret));
    fake.resetCalls();

    try store.load(&key, .refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(demo_secret));
    try testing.expectEqualSlices(FakeSecItem.Call, &.{ .copy, .copy }, fake.recordedCalls());
    try testing.expectEqualStrings(macos.v2_service, fake.recordedItems()[0].serviceText());
    try testing.expectEqualStrings(macos.legacy_service, fake.recordedItems()[1].serviceText());
    try testing.expectEqual(AuthenticationUI.fail, fake.recordedItems()[0].authentication_ui);
    try testing.expectEqual(AuthenticationUI.fail, fake.recordedItems()[1].authentication_ui);

    fake.resetCalls();
    try store.save(&key, .refresh_token, &fresh_secret);
    try testing.expectEqualSlices(FakeSecItem.Call, &.{ .update, .add }, fake.recordedCalls());
    for (fake.recordedItems()) |item| {
        try testing.expectEqualStrings(macos.v2_service, item.serviceText());
        try testing.expectEqual(AuthenticationUI.fail, item.authentication_ui);
    }

    loaded.wipe();
    fake.resetCalls();
    try store.load(&key, .refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(other_secret));
    try testing.expectEqualSlices(FakeSecItem.Call, &.{.copy}, fake.recordedCalls());
    try testing.expectEqualStrings(macos.v2_service, fake.recordedItems()[0].serviceText());

    try store.remove(&key, .refresh_token);
    loaded.wipe();
    fake.resetCalls();
    try store.load(&key, .refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(demo_secret));
}

test "SecItem backend round-trips every credential slot inside this app's namespace" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = undefined;
    var adapter: macos.KeychainStore = undefined;
    const store = try wiredKeychain(&fake, &backend, &adapter);

    const key = demoKey();
    var access = try Credential.init(demo_secret);
    defer access.wipe();
    var refresh = try Credential.init(other_secret);
    defer refresh.wipe();
    var loaded: Credential = .empty;
    defer loaded.wipe();

    const slots = [_]CredentialKind{ .access_token, .refresh_token, .staged_refresh_token, .codex_cli_record, .codex_auth_backup };
    for (slots) |slot| {
        try testing.expect(!try store.contains(&key, slot));
        try testing.expectError(error.NotFound, store.load(&key, slot, &loaded));
    }
    try store.save(&key, .access_token, &access);
    try store.save(&key, .refresh_token, &refresh);
    try store.save(&key, .staged_refresh_token, &refresh);
    try store.save(&key, .codex_cli_record, &refresh);
    try store.save(&key, .codex_auth_backup, &refresh);

    try store.load(&key, .access_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(demo_secret));
    try store.load(&key, .staged_refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(other_secret));
    for (slots) |slot| try testing.expect(try store.contains(&key, slot));

    try store.remove(&key, .staged_refresh_token);
    try testing.expect(!try store.contains(&key, .staged_refresh_token));
    try testing.expect(try store.contains(&key, .refresh_token));

    var seen_labels: usize = 0;
    for (fake.recordedItems()) |*item| {
        try testing.expectEqualStrings(macos.default_service, item.serviceText());
        try testing.expectEqual(ItemClass.generic_password, item.class);
        try testing.expectEqual(Accessibility.when_unlocked_this_device_only, item.accessibility);
        try testing.expect(!item.synchronizable);
        for ([_][]const u8{ "claude-demo.access", "claude-demo.refresh", "claude-demo.refresh-staged", "claude-demo.codex-cli", "claude-demo.codex-auth" }) |label| {
            if (std.mem.eql(u8, item.accountText(), label)) seen_labels += 1;
        }
    }
    try testing.expectEqual(fake.call_count, seen_labels);

    const other_key = try AccountKey.init("codex-demo");
    try testing.expect(!try store.contains(&other_key, .access_token));

    try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&fake), demo_secret) == null);
    try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&fake), other_secret) == null);
}

test "SecItem upsert updates before it adds and closes a lost add race" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = undefined;
    var adapter: macos.KeychainStore = undefined;
    const store = try wiredKeychain(&fake, &backend, &adapter);

    const key = demoKey();
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();
    var replacement = try Credential.init(other_secret);
    defer replacement.wipe();
    var loaded: Credential = .empty;
    defer loaded.wipe();

    fake.resetCalls();
    try store.save(&key, .refresh_token, &credential);
    try testing.expectEqualSlices(FakeSecItem.Call, &.{ .update, .add }, fake.recordedCalls());

    fake.resetCalls();
    try store.save(&key, .refresh_token, &replacement);
    try testing.expectEqualSlices(FakeSecItem.Call, &.{.update}, fake.recordedCalls());
    try store.load(&key, .refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(other_secret));

    fake.resetCalls();
    fake.duplicate_adds = 1;
    try store.save(&key, .staged_refresh_token, &credential);
    try testing.expectEqualSlices(FakeSecItem.Call, &.{ .update, .add, .update }, fake.recordedCalls());
    try store.load(&key, .staged_refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(demo_secret));
}

test "SecItem delete is idempotent and reports an absent item as absent" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = undefined;
    var adapter: macos.KeychainStore = undefined;
    const store = try wiredKeychain(&fake, &backend, &adapter);

    const key = demoKey();
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();

    try store.remove(&key, .staged_refresh_token);
    try store.save(&key, .staged_refresh_token, &credential);
    try store.remove(&key, .staged_refresh_token);
    try store.remove(&key, .staged_refresh_token);
    try testing.expect(!try store.contains(&key, .staged_refresh_token));
}

test "SecItem failures surface as store errors without inventing a credential" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = undefined;
    var adapter: macos.KeychainStore = undefined;
    const store = try wiredKeychain(&fake, &backend, &adapter);

    const key = demoKey();
    var credential = try Credential.init(demo_secret);
    defer credential.wipe();
    var loaded: Credential = .empty;
    defer loaded.wipe();

    fake.fail_call = .copy;
    fake.fail_status = macos.status_interaction_not_allowed;
    try testing.expectError(error.RepairRequired, store.load(&key, .access_token, &loaded));
    try testing.expect(loaded.isEmpty());

    fake.fail_call = .matches;
    fake.fail_status = macos.status_auth_failed;
    try testing.expectError(error.RepairRequired, store.contains(&key, .access_token));

    fake.fail_call = .update;
    fake.fail_status = macos.status_disk_full;
    try testing.expectError(error.StoreFull, store.save(&key, .access_token, &credential));

    fake.fail_call = .add;
    fake.fail_status = macos.status_missing_entitlement;
    try testing.expectError(error.AccessDenied, store.save(&key, .access_token, &credential));

    fake.fail_call = .delete;
    fake.fail_status = macos.status_not_available;
    try testing.expectError(error.Unavailable, store.remove(&key, .access_token));

    fake.fail_call = null;
    try testing.expect(!try store.contains(&key, .access_token));
}

test "OSStatus values map onto the credential-store error contract" {
    const load_cases = [_]struct { status: macos.OSStatus, expected: LoadError }{
        .{ .status = macos.status_item_not_found, .expected = error.NotFound },
        .{ .status = macos.status_no_such_keychain, .expected = error.NotFound },
        .{ .status = macos.status_auth_failed, .expected = error.RepairRequired },
        .{ .status = macos.status_user_canceled, .expected = error.AccessDenied },
        .{ .status = macos.status_missing_entitlement, .expected = error.AccessDenied },
        .{ .status = macos.status_interaction_not_allowed, .expected = error.RepairRequired },
        .{ .status = macos.status_not_available, .expected = error.Unavailable },
        .{ .status = macos.status_allocate, .expected = error.Unavailable },
        .{ .status = macos.status_data_too_large, .expected = error.ValueTooLarge },
        .{ .status = macos.status_buffer_too_small, .expected = error.ValueTooLarge },
        .{ .status = macos.status_decode, .expected = error.Corrupt },
        .{ .status = macos.status_invalid_keychain, .expected = error.Corrupt },
        .{ .status = macos.status_param, .expected = error.Corrupt },
        .{ .status = macos.status_unimplemented, .expected = error.Unsupported },
        .{ .status = macos.status_io, .expected = error.Io },
        .{ .status = -12345, .expected = error.Io },
    };
    for (load_cases) |case| try testing.expectEqual(case.expected, macos.loadErrorFromStatus(case.status));

    const save_cases = [_]struct { status: macos.OSStatus, expected: SaveError }{
        .{ .status = macos.status_read_only, .expected = error.AccessDenied },
        .{ .status = macos.status_user_canceled, .expected = error.AccessDenied },
        .{ .status = macos.status_missing_entitlement, .expected = error.AccessDenied },
        .{ .status = macos.status_interaction_not_allowed, .expected = error.RepairRequired },
        .{ .status = macos.status_no_such_keychain, .expected = error.Unavailable },
        .{ .status = macos.status_data_too_large, .expected = error.ValueTooLarge },
        .{ .status = macos.status_disk_full, .expected = error.StoreFull },
        .{ .status = macos.status_unimplemented, .expected = error.Unsupported },
        .{ .status = macos.status_item_not_found, .expected = error.Io },
    };
    for (save_cases) |case| try testing.expectEqual(case.expected, macos.saveErrorFromStatus(case.status));

    const remove_cases = [_]struct { status: macos.OSStatus, expected: RemoveError }{
        .{ .status = macos.status_auth_failed, .expected = error.RepairRequired },
        .{ .status = macos.status_not_available, .expected = error.Unavailable },
        .{ .status = macos.status_unimplemented, .expected = error.Unsupported },
        .{ .status = macos.status_decode, .expected = error.Io },
    };
    for (remove_cases) |case| try testing.expectEqual(case.expected, macos.removeErrorFromStatus(case.status));
}

test "SecItem backend refuses any query outside this app's own namespace" {
    var fake: FakeSecItem = .{};
    defer fake.deinit();
    var backend: macos.SecItemStore = .init(fake.api());
    const wired = backend.backend();

    var credential = try Credential.init(demo_secret);
    defer credential.wipe();
    var loaded: Credential = .empty;
    defer loaded.wipe();

    const rejected = [_]ItemQuery{
        .{ .service = "com.google.Chrome", .account = "claude-demo.access" },
        .{ .service = "Chrome Safe Storage", .account = "claude-demo.access" },
        .{ .class = .internet_password, .service = macos.default_service, .account = "claude-demo.access" },
        .{ .service = macos.default_service, .account = "claude-demo.access", .synchronizable = true },
    };
    for (rejected) |item| {
        try testing.expectError(error.AccessDenied, wired.vtable.copy(wired.context, item, &loaded));
        try testing.expectError(error.AccessDenied, wired.vtable.exists(wired.context, item));
        try testing.expectError(error.AccessDenied, wired.vtable.upsert(wired.context, item, &credential));
        try testing.expectError(error.AccessDenied, wired.vtable.delete(wired.context, item));
    }

    try testing.expectEqual(@as(usize, 0), fake.call_count);
    try testing.expect(loaded.isEmpty());
}
