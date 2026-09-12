const std = @import("std");
const builtin = @import("builtin");
const app_service = @import("app_service.zig");
pub const bridge_json = @import("bridge_json.zig");
const coordinator = @import("coordinator.zig");
const keychain = @import("keychain.zig");
const proxy_control = @import("proxy_control_client.zig");
const proxy_import_runner = @import("proxy_import_runner.zig");
const proxy_launch_runner = @import("proxy_launch_runner.zig");
const proxy_service_manager = @import("proxy_service_manager.zig");
const codex_routing_editor = @import("codex_routing_editor.zig");
const transport = @import("process_jsonl.zig");
const runtime_paths = @import("runtime_paths.zig");
const shell = @import("shell_model.zig");
const provenance = @import("core_provenance");
const provenance_c = provenance.marker ++ "\x00";

const allocator = std.heap.c_allocator;
const max_cli_version_output_bytes: usize = 256;
pub const minimum_codex_cli_version = "0.146.0";
const bundled_helpers_suffix = "Contents/Helpers";

const invalid_projection: [:0]const u8 =
    "{\"schema\":1,\"generation\":0,\"serialize_error\":\"invalid_handle\"}";

pub const CliVersionCompatibility = enum { unknown, too_old, supported };

pub fn classifyCliVersionOutput(output: []const u8, minimum: []const u8) CliVersionCompatibility {
    const minimum_version = std.SemanticVersion.parse(minimum) catch return .unknown;
    var tokens = std.mem.tokenizeAny(u8, output, " \t\r\n()[]{}:,;");
    while (tokens.next()) |raw| {
        const token = if (raw.len > 1 and raw[0] == 'v') raw[1..] else raw;
        const version = std.SemanticVersion.parse(token) catch continue;
        return switch (version.order(minimum_version)) {
            .lt => .too_old,
            .eq, .gt => .supported,
        };
    }
    return .unknown;
}

fn localCliVersionCompatibility(
    runtime_allocator: std.mem.Allocator,
    io: std.Io,
    parent_environ: *const std.process.Environ.Map,
    executable: []const u8,
    helpers_directory: []const u8,
    minimum: []const u8,
) CliVersionCompatibility {
    if (executable.len == 0) return .unknown;
    var child_env = parent_environ.clone(runtime_allocator) catch return .unknown;
    defer child_env.deinit();
    transport.prepareProviderChildEnvironment(
        &child_env,
        executable,
        helpers_directory,
    ) catch return .unknown;
    const argv = [_][]const u8{ executable, "--version" };
    const result = std.process.run(runtime_allocator, io, .{
        .argv = &argv,
        .environ_map = &child_env,
        .stdout_limit = .limited(max_cli_version_output_bytes),
        .stderr_limit = .limited(max_cli_version_output_bytes),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } },
    }) catch return .unknown;
    defer runtime_allocator.free(result.stdout);
    defer runtime_allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return .unknown,
        else => return .unknown,
    }
    const stdout_compatibility = classifyCliVersionOutput(result.stdout, minimum);
    if (stdout_compatibility != .unknown) return stdout_compatibility;
    return classifyCliVersionOutput(result.stderr, minimum);
}

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    layout: runtime_paths.Layout,
    data_dir: std.Io.Dir,
    sink_backing: coordinator.FileDocumentSink,
    directories_backing: app_service.FileDirectories,
    keychain_backing: keychain.macos.SystemKeychain,
    codex_launcher: app_service.ChildCodexLauncher,
    login_launcher: app_service.ProcessLoginLauncher,
    proxy_http: proxy_control.LoopbackExchange,
    proxy_import: proxy_import_runner.ProcessRunner,
    proxy_node: proxy_import_runner.FilesystemNodeResolver,
    proxy_launch: proxy_launch_runner.ProcessRunner,
    proxy_artifacts: proxy_service_manager.FileArtifacts,
    proxy_routing: codex_routing_editor.FileEditor,
    proxy_health: proxy_service_manager.LoopbackHealth,
    proxy_service_paths: proxy_service_manager.Paths,
    proxy_bundle_identity: proxy_service_manager.BundleIdentity,
    keys: app_service.RandomKeySource,
    codex_executable: app_service.ExecutablePath,
    provider_helpers: runtime_paths.Path,
    codex_cli_compatibility: CliVersionCompatibility = .unknown,
    core: *coordinator.Coordinator,
    service: *app_service.Service,
    load_report: coordinator.LoadReport = .{},

    pub const StartError = error{
        MissingHome,
        InvalidRoot,
        DirectoryUnavailable,
        KeychainUnavailable,
        OutOfMemory,
    };

    pub fn start(
        runtime_allocator: std.mem.Allocator,
        io: std.Io,
        environ: *const std.process.Environ.Map,
    ) StartError!*Runtime {
        const home = environ.get("HOME") orelse return error.MissingHome;
        const layout = runtime_paths.Layout.fromHomeDir(home) catch return error.InvalidRoot;

        const self = try runtime_allocator.create(Runtime);
        errdefer runtime_allocator.destroy(self);
        self.* = .{
            .allocator = runtime_allocator,
            .io = io,
            .layout = layout,
            .data_dir = undefined,
            .sink_backing = undefined,
            .directories_backing = .{ .io = io, .layout = layout },
            .keychain_backing = keychain.macos.SystemKeychain.init(keychain.macos.default_service) catch
                return error.KeychainUnavailable,
            .codex_launcher = undefined,
            .login_launcher = .{ .io = io, .allocator = runtime_allocator },
            .proxy_http = proxy_control.LoopbackExchange.init(runtime_allocator, io),
            .proxy_import = proxy_import_runner.ProcessRunner.init(io, runtime_allocator),
            .proxy_node = proxy_import_runner.FilesystemNodeResolver.init(io),
            .proxy_launch = proxy_launch_runner.ProcessRunner.init(io, runtime_allocator),
            .proxy_artifacts = proxy_service_manager.FileArtifacts.init(io, runtime_allocator),
            .proxy_routing = codex_routing_editor.FileEditor.init(io, runtime_allocator),
            .proxy_health = undefined,
            .proxy_service_paths = undefined,
            .proxy_bundle_identity = undefined,
            .keys = .{ .io = io },
            .codex_executable = .{},
            .provider_helpers = .{},
            .core = undefined,
            .service = undefined,
        };

        const directories = self.directories_backing.directories();
        directories.ensure(layout.rootPath()) catch return error.DirectoryUnavailable;
        const accounts_dir = layout.accountsDir() catch return error.InvalidRoot;
        directories.ensure(accounts_dir.slice()) catch return error.DirectoryUnavailable;
        self.data_dir = std.Io.Dir.openDirAbsolute(io, layout.rootPath(), .{}) catch
            return error.DirectoryUnavailable;
        errdefer self.data_dir.close(io);
        self.sink_backing = .{ .io = io, .dir = self.data_dir };

        const app_path = deriveCanonicalAppPath(runtime_allocator, io, home) catch return error.InvalidRoot;
        defer runtime_allocator.free(app_path);
        self.provider_helpers = deriveExistingBundledHelpersPath(io, app_path);
        self.login_launcher.helpers_directory = self.provider_helpers.slice();

        const path_variable = environ.get("PATH") orelse "";
        _ = app_service.resolveProviderExecutable(io, path_variable, home, "codex", &self.codex_executable);
        self.codex_cli_compatibility = localCliVersionCompatibility(
            runtime_allocator,
            io,
            environ,
            self.codex_executable.slice(),
            self.provider_helpers.slice(),
            minimum_codex_cli_version,
        );

        self.codex_launcher = .{
            .io = io,
            .allocator = runtime_allocator,
            .executable = self.codex_executable.slice(),
            .helpers_directory = self.provider_helpers.slice(),
            .parent_env = .{ .map = environ },
        };
        self.core = try coordinator.Coordinator.create(runtime_allocator, .{
            .layout = layout,
            .target = .{
                .codex_executable = self.codex_executable.slice(),
                .codex_cli_version = if (self.codex_cli_compatibility == .supported) minimum_codex_cli_version else "unknown",
            },
        });
        errdefer self.core.destroy();
        self.service = try app_service.Service.create(runtime_allocator, self.core);
        errdefer self.service.destroy();

        self.load_report = self.service.load(io, self.data_dir);
        const expanded_config = proxy_import_runner.expandConfigPath(self.service.proxyState().settings.config_path.slice(), home) catch return error.InvalidRoot;
        self.proxy_http.useConfigPath(expanded_config.slice()) catch return error.InvalidRoot;
        self.proxy_service_paths = proxy_service_manager.Paths.init(
            home,
            app_path,
            layout.rootPath(),
            expanded_config.slice(),
            @intCast(std.c.getuid()),
        ) catch return error.InvalidRoot;
        self.proxy_bundle_identity = proxy_service_manager.loadBundleIdentity(runtime_allocator, io, app_path) catch
            proxy_service_manager.BundleIdentity.init(
                "0000000000000000000000000000000000000000",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "v0.0.0",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "0000000000000000000000000000000000000000000000000000000000000000",
            ) catch unreachable;
        self.proxy_health = proxy_service_manager.LoopbackHealth.init(runtime_allocator, self.proxy_http.exchange());
        const lifecycle = self.proxyLifecycleLive();

        if (!builtin.is_test) self.service.discoverProxyService(lifecycle);
        self.service.attach(.{
            .io = io,
            .allocator = runtime_allocator,
            .sink = self.sink_backing.sink(),
            .credentials = self.keychain_backing.store(),
            .codex_launcher = self.codex_launcher.launcher(),
            .codex_cli_too_old = self.codex_cli_compatibility == .too_old,
            .login_launcher = self.login_launcher.launcher(),
            .directories = directories,
            .keys = self.keys.source(),
            .parent_env = .{ .map = environ },
            .proxy_exchange = self.proxy_http.exchange(),
            .proxy_importer = self.proxy_import.runner(),
            .proxy_node_resolver = self.proxy_node.resolver(),
            .proxy_service = lifecycle,
        });
        self.service.restoreCodexAuthBackups();
        return self;
    }

    pub fn stop(self: *Runtime) void {
        self.service.destroy();
        self.core.destroy();
        self.data_dir.close(self.io);
        self.allocator.destroy(self);
    }

    pub fn port(self: *Runtime) @import("ui_model.zig").ServicePort {
        return self.service.port();
    }

    fn proxyLifecycleLive(self: *Runtime) proxy_service_manager.Live {
        return .{
            .io = self.io,
            .allocator = self.allocator,
            .paths = self.proxy_service_paths,
            .identity = self.proxy_bundle_identity,
            .launch = self.proxy_launch.runner(),
            .artifacts = self.proxy_artifacts.store(),
            .routing = self.proxy_routing.editor(),
            .health = self.proxy_health.probe(),
            .importer = self.proxy_import.runner(),
            .control_base_url = self.service.proxyState().settings.base_url.slice(),
        };
    }
};

fn deriveCanonicalAppPath(allocator_: std.mem.Allocator, io: std.Io, home: []const u8) ![]u8 {
    const executable = try std.process.executablePathAlloc(io, allocator_);
    defer allocator_.free(executable);
    const marker = "/Contents/MacOS/";
    if (std.mem.lastIndexOf(u8, executable, marker)) |index| {
        return allocator_.dupe(u8, executable[0..index]);
    }

    return std.fmt.allocPrint(allocator_, "{s}/CodexMulti.app", .{home});
}

fn deriveExistingBundledHelpersPath(io: std.Io, app_path: []const u8) runtime_paths.Path {
    var storage: [runtime_paths.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&storage, "{s}/{s}", .{ app_path, bundled_helpers_suffix }) catch return .{};
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch return .{};
    if (stat.kind != .directory) return .{};
    return runtime_paths.Path.init(path) catch .{};
}

pub const cm_service = struct {
    threaded: std.Io.Threaded,
    environ: std.process.Environ.Map,
    runtime: ?*Runtime = null,
    runtime_projection: bridge_json.RuntimeProjection = .{},
    model: shell.Model = .{},
    effects: shell.Effects = .{},
    generation: u64 = 0,
    projection: ?[:0]u8 = null,
    projection_allocator: ?std.mem.Allocator = null,
    fallback_projection: [128]u8 = @splat(0),
};

fn runtimeError(err: Runtime.StartError) bridge_json.RuntimeError {
    return switch (err) {
        error.MissingHome => .missing_home,
        error.InvalidRoot => .invalid_root,
        error.DirectoryUnavailable => .directory_unavailable,
        error.KeychainUnavailable => .keychain_unavailable,
        error.OutOfMemory => .out_of_memory,
    };
}

fn libcEnvironmentBlock() std.process.Environ.Block {
    const values = std.c.environ;
    var count: usize = 0;
    while (values[count] != null) : (count += 1) {}
    return .{ .slice = values[0..count :null] };
}

pub export fn cm_service_version() callconv(.c) u32 {
    return 1;
}

pub export fn cm_copy_text(language: u8, key: ?[*]const u8, key_len: usize, out: ?[*]u8, capacity: usize) callconv(.c) usize {
    const input = key orelse return 0;
    if (key_len > 128) return 0;
    const copy = @import("strings.zig").catalog(if (language == 1) .ko else .en);
    const value = copy.lookup(input[0..key_len]) orelse return 0;
    if (out) |buffer| {
        if (capacity >= value.len) @memcpy(buffer[0..value.len], value);
    }
    return value.len;
}

pub export fn cm_service_create() callconv(.c) ?*cm_service {
    const service = allocator.create(cm_service) catch return null;
    const environ_block = libcEnvironmentBlock();
    service.threaded = std.Io.Threaded.init(allocator, .{ .environ = .{ .block = environ_block } });
    errdefer service.threaded.deinit();
    service.environ = std.process.Environ.createMap(.{ .block = environ_block }, allocator) catch {
        service.threaded.deinit();
        allocator.destroy(service);
        return null;
    };
    service.runtime = null;
    service.runtime_projection = .{};
    service.model = shell.initialModel(.system);
    service.effects = .{};
    service.generation = 0;
    service.projection = null;
    service.projection_allocator = null;
    service.fallback_projection = @splat(0);

    service.runtime = Runtime.start(allocator, service.threaded.io(), &service.environ) catch |err| {
        service.runtime_projection.@"error" = runtimeError(err);
        shell.reproject(&service.model);
        return service;
    };
    const runtime = service.runtime.?;
    service.runtime_projection = .{
        .started = true,
        .codex_cli_version_exact = runtime.codex_cli_compatibility == .supported,
    };
    service.model.service = runtime.port();
    shell.reproject(&service.model);
    return service;
}

pub export fn cm_service_destroy(service: ?*cm_service) callconv(.c) void {
    const self = service orelse return;
    if (self.projection) |bytes| self.projection_allocator.?.free(bytes);
    self.effects.clear();
    if (self.runtime) |runtime| runtime.stop();
    self.environ.deinit();
    self.threaded.deinit();
    allocator.destroy(self);
}

pub fn submitWithAllocator(service: ?*cm_service, intent_json: ?[]const u8, parse_allocator: std.mem.Allocator) i32 {
    const self = service orelse return bridge_json.CM_ERR_HANDLE;
    const bytes = intent_json orelse return bridge_json.CM_ERR_JSON;
    if (bytes.len > shell.max_intent_json_bytes) return bridge_json.CM_ERR_JSON;
    var parsed = switch (bridge_json.parseIntent(parse_allocator, bytes)) {
        .rejected => |code| return code,
        .accepted => |accepted| accepted,
    };
    defer parsed.deinit();
    shell.update(&self.model, parsed.intent, &self.effects);
    shell.reproject(&self.model);
    self.generation +%= 1;
    return bridge_json.CM_OK;
}

pub export fn cm_service_submit(service: ?*cm_service, intent_json: ?[*:0]const u8) callconv(.c) i32 {
    if (service == null) return bridge_json.CM_ERR_HANDLE;
    const input = intent_json orelse return bridge_json.CM_ERR_JSON;
    var input_len: usize = 0;
    while (input_len <= shell.max_intent_json_bytes and input[input_len] != 0) : (input_len += 1) {}
    if (input_len > shell.max_intent_json_bytes) return bridge_json.CM_ERR_JSON;
    return submitWithAllocator(service, input[0..input_len], allocator);
}

pub export fn cm_service_pump(service: ?*cm_service, now_unix_s: i64) callconv(.c) void {
    const self = service orelse return;
    shell.pump(&self.model, now_unix_s);
    if (!projectionMatchesCached(self)) self.generation +%= 1;
}

fn projectionMatchesCached(self: *cm_service) bool {
    const previous = self.projection orelse return false;
    const current = bridge_json.serialize(
        allocator,
        self.generation,
        self.runtime_projection,
        &self.model,
        &self.effects,
    ) catch return false;
    defer allocator.free(current);
    return std.mem.eql(u8, previous, current);
}

fn allocationFailureProjection(self: *cm_service) [*:0]const u8 {
    const bytes = std.fmt.bufPrintZ(&self.fallback_projection, "{{\"schema\":1,\"generation\":{d},\"serialize_error\":\"out_of_memory\"}}", .{self.generation}) catch unreachable;
    return bytes.ptr;
}

pub fn projectWithAllocator(service: ?*cm_service, projection_allocator: std.mem.Allocator) [*:0]const u8 {
    const self = service orelse return invalid_projection.ptr;
    if (self.projection) |bytes| {
        self.projection_allocator.?.free(bytes);
        self.projection = null;
        self.projection_allocator = null;
    }
    const bytes = bridge_json.serialize(
        projection_allocator,
        self.generation,
        self.runtime_projection,
        &self.model,
        &self.effects,
    ) catch return allocationFailureProjection(self);
    const terminated = projection_allocator.allocSentinel(u8, bytes.len, 0) catch {
        projection_allocator.free(bytes);
        return allocationFailureProjection(self);
    };
    @memcpy(terminated, bytes);
    projection_allocator.free(bytes);
    self.projection = terminated;
    self.projection_allocator = projection_allocator;
    self.effects.clear();
    return terminated.ptr;
}

pub export fn cm_service_project(service: ?*cm_service) callconv(.c) [*:0]const u8 {
    return projectWithAllocator(service, allocator);
}

pub export fn cm_service_provenance() callconv(.c) [*:0]const u8 {
    return provenance_c[0..provenance.marker.len :0].ptr;
}

pub export fn cm_service_keychain_probe(service: ?*cm_service, out: ?[*]u8, cap: usize) callconv(.c) i32 {
    const self = service orelse return -1;
    const runtime = self.runtime orelse return -3;
    // Runtime creation has actually passed signer validation. Do not inspect
    // credential values, and never report success for the detached shell.
    var buffer: [192]u8 = undefined;
    const bytes = std.fmt.bufPrint(
        &buffer,
        "{{\"schema\":1,\"signer_valid\":true,\"runtime_started\":true,\"account_count\":{d},\"accounts\":[]}}\n",
        .{runtime.load_report.accounts_loaded},
    ) catch return -2;
    if (bytes.len > cap or (bytes.len != 0 and out == null)) return -2;
    if (bytes.len != 0) @memcpy(out.?[0..bytes.len], bytes);
    return @intCast(bytes.len);
}
