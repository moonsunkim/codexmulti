const std = @import("std");
const domain = @import("../domain.zig");
const proxy = @import("../proxy_control_client.zig");
const runtime_paths = @import("../runtime_paths.zig");
const store = @import("../store.zig");

const testing = std.testing;

const fixture_root = "/private/tmp/codexmulti-fixture/" ++ runtime_paths.app_data_directory_name;
const fixture_config = "/private/tmp/codexmulti-fixture/proxy/config.json";
const fixture_auth_a = fixture_root ++ "/accounts/profile-a/codex/auth.json";
const fixture_auth_b = fixture_root ++ "/accounts/profile-b/codex/auth.json";

const status_v1 =
    \\{"version":1,"active":"codex-1","cursor":"codex-1","in_flight":0,"accounts":[{"name":"codex-1","state":"READY","cooldown_until":null,"reason":null,"token_expires_at":"2030-01-01T00:00:00.000Z","in_flight":0}]}
;

const status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ fixture_config ++
    "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":1,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Primary\",\"auth_file\":\"" ++ fixture_auth_a ++
    "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":\"2030-01-01T00:00:00.000Z\",\"in_flight\":0},{" ++
    "\"name\":\"codex-2\",\"label\":null,\"auth_file\":\"" ++ fixture_auth_b ++
    "\",\"state\":\"COOLDOWN\",\"cooldown_until\":\"2030-01-01T00:01:02Z\",\"reason\":\"usage_limit_reached\",\"token_expires_at\":null,\"in_flight\":1}]}";

const FakeExchange = struct {
    calls: usize = 0,
    response_status: u16 = 200,
    response_body: []const u8 = status_v2,
    method: proxy.Method = .get,
    path: [proxy.max_request_path_bytes]u8 = @splat(0),
    path_len: usize = 0,
    body: [proxy.max_request_body_bytes]u8 = @splat(0),
    body_len: usize = 0,
    content_type: bool = false,

    const vtable: proxy.Exchange.VTable = .{ .perform = perform };

    fn exchange(self: *FakeExchange) proxy.Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    fn perform(context: *anyopaque, request: proxy.Request, response_buffer: []u8) proxy.TransportError!proxy.ExchangeResult {
        const self: *FakeExchange = @ptrCast(@alignCast(context));
        self.calls += 1;
        self.method = request.method;
        self.path_len = request.path.len;
        @memcpy(self.path[0..request.path.len], request.path);
        self.body_len = request.body.len;
        @memcpy(self.body[0..request.body.len], request.body);
        self.content_type = request.content_type_json;
        if (self.response_body.len > response_buffer.len) return error.ResponseTooLarge;
        @memcpy(response_buffer[0..self.response_body.len], self.response_body);
        return .{ .status = self.response_status, .body_len = self.response_body.len };
    }

    fn pathText(self: *const FakeExchange) []const u8 {
        return self.path[0..self.path_len];
    }

    fn bodyText(self: *const FakeExchange) []const u8 {
        return self.body[0..self.body_len];
    }
};

test "proxy base URL accepts only bounded numeric IPv4 loopback HTTP" {
    var url = try proxy.BaseUrl.init("http://127.0.0.1:8787");
    try testing.expectEqualStrings("http://127.0.0.1:8787", url.slice());
    try testing.expectEqual(@as(u16, 8787), url.port);

    const rejected = [_][]const u8{
        "https://127.0.0.1:8787",
        "http://localhost:8787",
        "http://127.0.0.1:0",
        "http://127.0.0.1:65536",
        "http://127.0.0.1:8787/extra",
        "http://user@127.0.0.1:8787",
        "http://127.0.0.1:8787?query=1",
        "http://127.0.0.1:8787#fragment",
    };
    for (rejected) |candidate| {
        try testing.expectError(error.InvalidBaseUrl, proxy.BaseUrl.init(candidate));
    }
}

test "status v1 parses for compatibility detection but cannot map accounts" {
    const status = try proxy.parseStatus(testing.allocator, status_v1);
    try testing.expectEqual(@as(u8, 1), status.version);
    try testing.expectEqual(@as(usize, 1), status.accountCount());
    try testing.expectEqual(proxy.AccountState.ready, status.accountAt(0).?.state);

    const layout = try runtime_paths.Layout.fromAppDataDir(fixture_root);
    try testing.expectError(error.IncompatibleVersion, proxy.mapStatus(status, &layout, &.{}));
}

test "status v2 parses bounded states and maps exact auth paths" {
    const status = try proxy.parseStatus(testing.allocator, status_v2);
    try testing.expectEqual(@as(u8, 2), status.version);
    try testing.expectEqual(@as(u32, 1), status.in_flight);
    try testing.expectEqual(@as(usize, 2), status.accountCount());
    try testing.expectEqual(proxy.AccountState.cooldown, status.accountAt(1).?.state);
    try testing.expectEqual(@as(?i64, 1_893_456_062), status.accountAt(1).?.cooldown_until_unix_s);
    try testing.expectEqual(@as(?i64, 1_893_456_000), status.accountAt(0).?.token_expires_at_unix_s);

    const layout = try runtime_paths.Layout.fromAppDataDir(fixture_root);
    const app_accounts = [_]proxy.AppAccount{
        .{ .app_id = "fixture-a", .storage_key = "profile-a", .label = "Primary", .provider = .codex, .enabled = true, .connected = true },
        .{ .app_id = "fixture-b", .storage_key = "profile-b", .label = "Secondary", .provider = .codex, .enabled = true, .connected = true },
        .{ .app_id = "fixture-c", .storage_key = "profile-c", .label = "Disabled", .provider = .codex, .enabled = false, .connected = true },
        .{ .app_id = "fixture-d", .storage_key = "profile-d", .label = "Other", .provider = .claude, .enabled = true, .connected = true },
    };
    const mapped = try proxy.mapStatus(status, &layout, &app_accounts);
    try testing.expectEqual(@as(usize, 2), mapped.accountCount());
    try testing.expect(mapped.accountAt(0).?.mapped);
    try testing.expectEqualStrings("fixture-a", mapped.accountAt(0).?.app_id.slice());
    try testing.expectEqualStrings("profile-b", mapped.accountAt(1).?.storage_key.slice());
    try testing.expectEqualStrings("Secondary", mapped.accountAt(1).?.label.slice());
    try testing.expectEqual(@as(?usize, 0), mapped.active_index);
}

test "F15 status parser carries proactive token renewal health without credential values" {
    const body =
        "{\"version\":2,\"config_path\":\"" ++ fixture_config ++
        "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
        "\"name\":\"codex-1\",\"label\":\"Primary\",\"auth_file\":\"" ++ fixture_auth_a ++
        "\",\"state\":\"INVALID\",\"cooldown_until\":null,\"reason\":\"invalid_credentials\"," ++
        "\"token_expires_at\":\"2030-01-01T00:00:00.000Z\",\"in_flight\":0," ++
        "\"token_refresh\":{\"last_ok_at\":\"2029-12-31T18:00:00.000Z\"," ++
        "\"last_error\":\"rejected\",\"next_attempt_at\":\"2030-01-01T02:00:00.000Z\"}}]}";

    const status = try proxy.parseStatus(testing.allocator, body);
    const account = status.accountAt(0).?;
    try testing.expectEqual(proxy.AccountState.invalid, account.state);
    try testing.expectEqual(@as(?i64, 1_893_434_400), account.token_refresh_last_ok_at_unix_s);
    try testing.expect(account.has_token_refresh_last_error);
    try testing.expectEqualStrings("rejected", account.token_refresh_last_error.slice());
    try testing.expectEqual(@as(?i64, 1_893_463_200), account.token_refresh_next_attempt_at_unix_s);
}

test "mapping refuses case path confusion and leaves unknown rows unmapped" {
    const confused =
        "{\"version\":2,\"config_path\":\"" ++ fixture_config ++
        "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
        "\"name\":\"codex-1\",\"label\":null,\"auth_file\":\"" ++ fixture_root ++
        "/accounts/Profile-A/codex/auth.json\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";
    const status = try proxy.parseStatus(testing.allocator, confused);
    const layout = try runtime_paths.Layout.fromAppDataDir(fixture_root);
    const accounts = [_]proxy.AppAccount{.{ .app_id = "fixture-a", .storage_key = "profile-a", .label = "Primary", .provider = .codex, .enabled = true, .connected = true }};
    const mapped = try proxy.mapStatus(status, &layout, &accounts);
    try testing.expect(!mapped.accountAt(0).?.mapped);
    try testing.expectError(error.UnmappedAccount, mapped.requireMapped("fixture-a"));
}

test "status parser rejects duplicates invalid paths versions and bounds" {
    const duplicate_name =
        \\{"version":2,"config_path":"/private/tmp/codexmulti-fixture/proxy/config.json","active":"same","cursor":"same","in_flight":0,"accounts":[{"name":"same","label":null,"auth_file":"/private/tmp/a/auth.json","state":"READY","cooldown_until":null,"reason":null,"token_expires_at":null,"in_flight":0},{"name":"same","label":null,"auth_file":"/private/tmp/b/auth.json","state":"READY","cooldown_until":null,"reason":null,"token_expires_at":null,"in_flight":0}]}
    ;
    const duplicate_path =
        \\{"version":2,"config_path":"/private/tmp/codexmulti-fixture/proxy/config.json","active":"one","cursor":"one","in_flight":0,"accounts":[{"name":"one","label":null,"auth_file":"/private/tmp/a/auth.json","state":"READY","cooldown_until":null,"reason":null,"token_expires_at":null,"in_flight":0},{"name":"two","label":null,"auth_file":"/private/tmp/a/auth.json","state":"READY","cooldown_until":null,"reason":null,"token_expires_at":null,"in_flight":0}]}
    ;
    const future = "{\"version\":3,\"accounts\":[]}";
    const traversal =
        \\{"version":2,"config_path":"/private/tmp/codexmulti-fixture/proxy/config.json","active":"one","cursor":"one","in_flight":0,"accounts":[{"name":"one","label":null,"auth_file":"/private/tmp/../escape/auth.json","state":"READY","cooldown_until":null,"reason":null,"token_expires_at":null,"in_flight":0}]}
    ;
    try testing.expectError(error.DuplicateAccountName, proxy.parseStatus(testing.allocator, duplicate_name));
    try testing.expectError(error.DuplicateAuthPath, proxy.parseStatus(testing.allocator, duplicate_path));
    try testing.expectError(error.IncompatibleVersion, proxy.parseStatus(testing.allocator, future));
    try testing.expectError(error.InvalidAuthPath, proxy.parseStatus(testing.allocator, traversal));

    var oversized: [proxy.max_response_body_bytes + 1]u8 = @splat(' ');
    oversized[0] = '{';
    try testing.expectError(error.ResponseTooLarge, proxy.parseStatus(testing.allocator, &oversized));
}

test "status v2 accepts every documented state and nullable timestamps" {
    const cases = [_]struct { wire: []const u8, expected: proxy.AccountState }{
        .{ .wire = "READY", .expected = .ready },
        .{ .wire = "COOLDOWN", .expected = .cooldown },
        .{ .wire = "PAUSED", .expected = .paused },
        .{ .wire = "INVALID", .expected = .invalid },
        .{ .wire = "REFRESHING", .expected = .refreshing },
    };
    for (cases) |case| {
        const body = try std.fmt.allocPrint(testing.allocator, "{{\"version\":2,\"config_path\":\"{s}\",\"active\":null,\"cursor\":\"one\",\"in_flight\":0,\"accounts\":[{{\"name\":\"one\",\"label\":null,\"auth_file\":\"/private/tmp/a/auth.json\",\"state\":\"{s}\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}}]}}", .{ fixture_config, case.wire });
        defer testing.allocator.free(body);
        const parsed = try proxy.parseStatus(testing.allocator, body);
        try testing.expectEqual(case.expected, parsed.accountAt(0).?.state);
        try testing.expect(parsed.accountAt(0).?.cooldown_until_unix_s == null);
        try testing.expect(parsed.accountAt(0).?.token_expires_at_unix_s == null);
    }
}

test "unknown response fields are discarded instead of entering mapped facts" {
    const extended =
        "{\"version\":2,\"config_path\":\"" ++ fixture_config ++
        "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"private_identity\":\"fixture-private\",\"accounts\":[{" ++
        "\"name\":\"codex-1\",\"label\":null,\"auth_file\":\"" ++ fixture_auth_a ++
        "\",\"state\":\"PAUSED\",\"cooldown_until\":null,\"reason\":\"operator_paused\",\"token_expires_at\":null,\"in_flight\":0,\"credential_material\":\"discard-me\"}]}";
    const status = try proxy.parseStatus(testing.allocator, extended);
    const layout = try runtime_paths.Layout.fromAppDataDir(fixture_root);
    const accounts = [_]proxy.AppAccount{.{ .app_id = "fixture-a", .storage_key = "profile-a", .label = "Primary", .provider = .codex, .enabled = true, .connected = true }};
    const mapped = try proxy.mapStatus(status, &layout, &accounts);
    const retained = std.mem.asBytes(&mapped);
    try testing.expect(std.mem.indexOf(u8, retained, "fixture-private") == null);
    try testing.expect(std.mem.indexOf(u8, retained, "discard-me") == null);
    try testing.expect(std.mem.indexOf(u8, retained, "/accounts/") == null);
}

test "client emits exact status switch pause reload and reload-config requests" {
    var fake: FakeExchange = .{};
    var client = try proxy.Client.init(testing.allocator, fake.exchange(), "http://127.0.0.1:8787");

    _ = try client.status();
    try testing.expectEqual(@as(usize, 1), fake.calls);
    try testing.expectEqual(proxy.Method.get, fake.method);
    try testing.expectEqualStrings("/_proxy/status", fake.pathText());
    try testing.expectEqualStrings("", fake.bodyText());
    try testing.expect(!fake.content_type);

    _ = try client.switchAccount("codex-2");
    try testing.expectEqual(proxy.Method.post, fake.method);
    try testing.expectEqualStrings("/_proxy/switch", fake.pathText());
    try testing.expectEqualStrings("{\"name\":\"codex-2\"}", fake.bodyText());
    try testing.expect(fake.content_type);

    fake.response_status = 202;
    fake.response_body = "{\"name\":\"codex-2\",\"state\":\"PAUSED\",\"in_flight\":1}";
    const receipt = try client.pauseAccount("codex-2");
    try testing.expectEqualStrings("/_proxy/accounts/codex-2/pause", fake.pathText());
    try testing.expectEqual(@as(u32, 1), receipt.in_flight);

    fake.response_status = 200;
    fake.response_body = status_v2;
    _ = try client.reloadAccount("codex-2");
    try testing.expectEqualStrings("/_proxy/accounts/codex-2/reload", fake.pathText());
    _ = try client.reloadConfig();
    try testing.expectEqualStrings("/_proxy/reload-config", fake.pathText());
    try testing.expectEqualStrings("{}", fake.bodyText());
}

test "client clears a stale cooldown with an exact POST and accepts only a 200 account row" {
    var fake: FakeExchange = .{};
    var client = try proxy.Client.init(testing.allocator, fake.exchange(), "http://127.0.0.1:8787");

    fake.response_status = 200;
    fake.response_body = "{\"name\":\"codex-2\",\"state\":\"READY\",\"cooldown_until\":null}";
    const receipt = try client.clearCooldown("codex-2");
    try testing.expectEqual(proxy.Method.post, fake.method);
    try testing.expectEqualStrings("/_proxy/accounts/codex-2/clear-cooldown", fake.pathText());
    try testing.expectEqualStrings("{}", fake.bodyText());
    try testing.expect(fake.content_type);
    try testing.expectEqualStrings("codex-2", receipt.name.slice());
    try testing.expectEqual(proxy.AccountState.ready, receipt.state);
    try testing.expectEqual(@as(?i64, null), receipt.cooldown_until_unix_s);

    fake.response_status = 404;
    fake.response_body = "{\"error\":\"unknown_account\"}";
    try testing.expectError(error.ApiRejected, client.clearCooldown("codex-9"));
    fake.response_status = 409;
    fake.response_body = "{\"error\":\"account_paused\"}";
    try testing.expectError(error.ApiRejected, client.clearCooldown("codex-2"));

    fake.response_status = 200;
    fake.response_body = "{\"name\":\"codex-3\",\"state\":\"READY\",\"cooldown_until\":null}";
    try testing.expectError(error.InvalidStatus, client.clearCooldown("codex-2"));
    try testing.expectError(error.InvalidAccountName, client.clearCooldown("../etc"));
}

test "client construction and parsing perform zero exchanges" {
    var fake: FakeExchange = .{};
    _ = try proxy.Client.init(testing.allocator, fake.exchange(), "http://127.0.0.1:8787");
    _ = try proxy.parseStatus(testing.allocator, status_v2);
    try testing.expectEqual(@as(usize, 0), fake.calls);
}

test "proxy settings and sanitized status documents round trip" {
    const settings: store.ProxySettingsDocument = .{
        .proxy = .{
            .base_url = store.default_proxy_base_url,
            .cli_path = store.default_proxy_cli_path,
            .config_path = store.default_proxy_config_path,
        },
        .last_synced_accounts_fingerprint = "fixture-fingerprint",
    };
    const settings_bytes = try store.encode(testing.allocator, settings);
    defer testing.allocator.free(settings_bytes);
    var loaded_settings = try store.decodeProxySettings(testing.allocator, settings_bytes);
    defer loaded_settings.deinit();
    try testing.expectEqualStrings(store.default_proxy_base_url, loaded_settings.value.proxy.base_url);

    try testing.expect(loaded_settings.value.proxy.node_path == null);
    const legacy =
        \\{"schema_version":1,"proxy":{"base_url":"http://127.0.0.1:8787","cli_path":"/private/tmp/proxy-cli","config_path":"~/proxy/config.json"},"last_synced_accounts_fingerprint":null}
    ;
    var loaded_legacy = try store.decodeProxySettings(testing.allocator, legacy);
    defer loaded_legacy.deinit();
    try testing.expect(loaded_legacy.value.proxy.node_path == null);
    const explicit: store.ProxySettingsDocument = .{ .proxy = .{
        .base_url = store.default_proxy_base_url,
        .cli_path = store.default_proxy_cli_path,
        .config_path = store.default_proxy_config_path,
        .node_path = "/private/tmp/proxy-node/bin/node",
    } };
    const explicit_bytes = try store.encode(testing.allocator, explicit);
    defer testing.allocator.free(explicit_bytes);
    var loaded_explicit = try store.decodeProxySettings(testing.allocator, explicit_bytes);
    defer loaded_explicit.deinit();
    try testing.expectEqualStrings("/private/tmp/proxy-node/bin/node", loaded_explicit.value.proxy.node_path.?);
    try testing.expectError(error.InvalidProxyPath, store.validateProxySettings(.{ .proxy = .{
        .base_url = store.default_proxy_base_url,
        .cli_path = store.default_proxy_cli_path,
        .config_path = store.default_proxy_config_path,
        .node_path = "node",
    } }));

    const accounts = [_]store.ProxyStoredAccount{.{
        .proxy_name = "codex-1",
        .storage_key = "profile-a",
        .label = "Primary",
        .state = .ready,
        .in_flight = 0,
        .active = true,
    }};
    const status: store.ProxyStatusDocument = .{
        .last_attempt = .{ .at_unix_s = 1_893_456_000, .result = .ok },
        .last_success = .{
            .checked_at_unix_s = 1_893_456_000,
            .api_version = 2,
            .active_storage_key = "profile-a",
            .cooldown_count = 0,
            .accounts = &accounts,
        },
    };
    const status_bytes = try store.encode(testing.allocator, status);
    defer testing.allocator.free(status_bytes);
    var loaded_status = try store.decodeProxyStatus(testing.allocator, status_bytes);
    defer loaded_status.deinit();
    try testing.expectEqual(@as(?u8, 2), if (loaded_status.value.last_success) |value| value.api_version else null);
    try testing.expect(std.mem.indexOf(u8, status_bytes, "/accounts/") == null);
}

test "proxy document validation rejects unknown fields versions and invalid settings" {
    const unknown =
        \\{"schema_version":1,"proxy":{"base_url":"http://127.0.0.1:8787","cli_path":"/private/tmp/proxy-cli","config_path":"~/proxy/config.json"},"last_synced_accounts_fingerprint":null,"unexpected":true}
    ;
    const wrong_version =
        \\{"schema_version":2,"proxy":{"base_url":"http://127.0.0.1:8787","cli_path":"/private/tmp/proxy-cli","config_path":"~/proxy/config.json"},"last_synced_accounts_fingerprint":null}
    ;
    try testing.expectError(error.UnknownField, store.decodeProxySettings(testing.allocator, unknown));
    try testing.expectError(error.UnsupportedSchemaVersion, store.decodeProxySettings(testing.allocator, wrong_version));
    try testing.expectError(error.InvalidProxyBaseUrl, store.validateProxySettings(.{ .proxy = .{
        .base_url = "http://localhost:8787",
        .cli_path = "/private/tmp/proxy-cli",
        .config_path = "~/proxy/config.json",
    } }));
}

test "proxy document atomic helpers replace whole files and remove sibling temps" {
    const directory = ".zig-cache/test-proxy-control-store";
    var cwd = std.Io.Dir.cwd();
    cwd.deleteTree(testing.io, directory) catch {};
    try cwd.createDirPath(testing.io, directory);
    defer cwd.deleteTree(testing.io, directory) catch {};
    var dir = try cwd.openDir(testing.io, directory, .{});
    defer dir.close(testing.io);

    try store.saveProxySettingsAtomic(testing.allocator, testing.io, dir, runtime_paths.proxy_settings_file_name, runtime_paths.proxy_settings_temp_file_name, .{});
    var settings = try store.loadProxySettings(testing.allocator, testing.io, dir, runtime_paths.proxy_settings_file_name);
    defer settings.deinit();
    try testing.expectEqualStrings(store.default_proxy_base_url, settings.value.proxy.base_url);
    try testing.expectError(error.FileNotFound, dir.statFile(testing.io, runtime_paths.proxy_settings_temp_file_name, .{}));

    try store.saveProxyStatusAtomic(testing.allocator, testing.io, dir, runtime_paths.proxy_status_file_name, runtime_paths.proxy_status_temp_file_name, .{});
    var status = try store.loadProxyStatus(testing.allocator, testing.io, dir, runtime_paths.proxy_status_file_name);
    defer status.deinit();
    try testing.expect(status.value.last_success == null);
    try testing.expectError(error.FileNotFound, dir.statFile(testing.io, runtime_paths.proxy_status_temp_file_name, .{}));
}

test "runtime layout derives the exact Codex auth file and reserves proxy documents" {
    const layout = try runtime_paths.Layout.fromAppDataDir(fixture_root);
    var auth_file = try layout.codexAuthFile("profile-a");
    try testing.expectEqualStrings(fixture_auth_a, auth_file.slice());
    try testing.expectEqualStrings("proxy-settings.json", runtime_paths.documentFileName(.proxy_settings));
    try testing.expectEqualStrings("proxy-status.json.tmp", runtime_paths.documentTempFileName(.proxy_status));
    try testing.expectError(error.ReservedSegment, runtime_paths.validateAccountSegment("proxy-settings.json"));
    try testing.expectError(error.ReservedSegment, runtime_paths.validateAccountSegment("proxy-status.json"));
    try testing.expect(!std.mem.eql(u8, fixture_auth_a, fixture_auth_b));
    _ = domain.Provider.codex;
}
