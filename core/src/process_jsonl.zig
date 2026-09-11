const std = @import("std");

pub const max_frame_bytes: usize = 32 * 1024;

pub const max_request_bytes: usize = 8 * 1024;

pub const max_interleaved_frames: usize = 64;

pub const max_envelope_scratch_bytes: usize = 1024;

pub const max_empty_reads: usize = 8;

pub const max_path_bytes: usize = 1024;
pub const max_env_value_bytes: usize = 8 * 1024;
pub const max_child_env_vars: usize = 32;

pub const default_request_timeout_ms: u32 = 15_000;
pub const default_startup_timeout_ms: u32 = 20_000;

pub const TransportError = error{
    Timeout,

    EndOfStream,

    Io,

    MalformedFrame,

    FrameTooLarge,

    TooManyFrames,

    RequestTooLarge,

    SpawnFailed,

    Unsupported,
    Canceled,
};

pub const Stream = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        arm: *const fn (context: *anyopaque, timeout_ms: u32) void,
        read: *const fn (context: *anyopaque, buffer: []u8) TransportError!usize,

        write: *const fn (context: *anyopaque, bytes: []const u8) TransportError!void,
    };

    pub fn arm(self: Stream, timeout_ms: u32) void {
        self.vtable.arm(self.context, timeout_ms);
    }

    pub fn read(self: Stream, buffer: []u8) TransportError!usize {
        return self.vtable.read(self.context, buffer);
    }

    pub fn write(self: Stream, bytes: []const u8) TransportError!void {
        return self.vtable.write(self.context, bytes);
    }
};

var unwired_context: u8 = 0;
const unwired_vtable: Stream.VTable = .{ .arm = unwiredArm, .read = unwiredRead, .write = unwiredWrite };

fn unwiredArm(_: *anyopaque, _: u32) void {}
fn unwiredRead(_: *anyopaque, _: []u8) TransportError!usize {
    return error.Unsupported;
}
fn unwiredWrite(_: *anyopaque, _: []const u8) TransportError!void {
    return error.Unsupported;
}

pub fn unwiredStream() Stream {
    return .{ .context = &unwired_context, .vtable = &unwired_vtable };
}

pub const FrameReader = struct {
    storage: []u8,

    start: usize = 0,

    end: usize = 0,

    scan: usize = 0,
    at_end_of_stream: bool = false,
    empty_reads: usize = 0,

    pub fn init(storage: []u8) FrameReader {
        return .{ .storage = storage };
    }

    pub fn takeBuffered(self: *FrameReader) ?[]const u8 {
        while (self.scan < self.end) {
            if (self.storage[self.scan] == '\n') {
                const line = self.storage[self.start..self.scan];
                self.start = self.scan + 1;
                self.scan = self.start;
                return trimFrame(line);
            }
            self.scan += 1;
        }
        return null;
    }

    pub fn next(self: *FrameReader, stream: Stream) TransportError![]const u8 {
        while (true) {
            if (self.takeBuffered()) |line| {
                if (line.len == 0) continue;
                return line;
            }
            if (self.at_end_of_stream) return error.EndOfStream;
            try self.fill(stream);
        }
    }

    fn fill(self: *FrameReader, stream: Stream) TransportError!void {
        self.compact();

        if (self.end == self.storage.len) return error.FrameTooLarge;
        const count = stream.read(self.storage[self.end..]) catch |err| switch (err) {
            error.EndOfStream => {
                self.at_end_of_stream = true;
                return;
            },
            else => |other| return other,
        };
        if (count == 0) {
            self.empty_reads += 1;
            if (self.empty_reads > max_empty_reads) return error.Io;
            return;
        }
        self.empty_reads = 0;
        self.end += count;
    }

    fn compact(self: *FrameReader) void {
        if (self.start == 0) return;
        const pending = self.end - self.start;
        if (pending != 0) std.mem.copyForwards(u8, self.storage[0..pending], self.storage[self.start..self.end]);
        self.scan -= self.start;
        self.start = 0;
        self.end = pending;
    }
};

fn trimFrame(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t\r");
}

pub const EnvelopeKind = enum {
    response,

    server_request,
    notification,

    unrecognized,
};

pub const Envelope = struct {
    id: ?i64 = null,
    has_id: bool = false,
    has_method: bool = false,
    has_result: bool = false,
    has_error: bool = false,

    pub fn kind(self: Envelope) EnvelopeKind {
        if (self.has_method) return if (self.has_id) .server_request else .notification;
        if (self.has_id and (self.has_result or self.has_error)) return .response;
        return .unrecognized;
    }

    pub fn isResponseTo(self: Envelope, id: i64) bool {
        if (self.kind() != .response) return false;
        const own = self.id orelse return false;
        return own == id;
    }
};

pub const FrameDescriptor = struct {
    kind: EnvelopeKind,
    byte_len: usize,
    id: ?i64 = null,

    pub fn of(frame: []const u8, envelope: Envelope) FrameDescriptor {
        return .{ .kind = envelope.kind(), .byte_len = frame.len, .id = envelope.id };
    }

    pub fn format(self: FrameDescriptor, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("frame kind={t} bytes={d}", .{ self.kind, self.byte_len });
        if (self.id) |id| try writer.print(" id={d}", .{id});
    }
};

pub fn classify(frame: []const u8) TransportError!Envelope {
    var scratch: [max_envelope_scratch_bytes]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&scratch);
    var scanner = std.json.Scanner.initCompleteInput(fba.allocator(), frame);
    defer scanner.deinit();

    switch (scanner.next() catch return error.MalformedFrame) {
        .object_begin => {},
        else => return error.MalformedFrame,
    }

    var envelope: Envelope = .{};
    while (true) {
        const key_token = scanner.nextAlloc(fba.allocator(), .alloc_if_needed) catch return error.MalformedFrame;
        const key = switch (key_token) {
            .object_end => break,
            .string => |text| text,
            .allocated_string => |text| text,
            else => return error.MalformedFrame,
        };

        if (std.mem.eql(u8, key, "id")) {
            envelope.has_id = true;
            const value_type = scanner.peekNextTokenType() catch return error.MalformedFrame;
            if (value_type == .number) {
                const token = scanner.next() catch return error.MalformedFrame;
                const text = switch (token) {
                    .number => |digits| digits,
                    else => return error.MalformedFrame,
                };
                envelope.id = std.fmt.parseInt(i64, text, 10) catch null;
            } else {
                if (value_type == .null) envelope.has_id = false;
                scanner.skipValue() catch return error.MalformedFrame;
            }
            continue;
        }

        if (std.mem.eql(u8, key, "method")) envelope.has_method = true;
        if (std.mem.eql(u8, key, "result")) envelope.has_result = true;
        if (std.mem.eql(u8, key, "error")) envelope.has_error = true;
        scanner.skipValue() catch return error.MalformedFrame;
    }

    switch (scanner.next() catch return error.MalformedFrame) {
        .end_of_document => {},
        else => return error.MalformedFrame,
    }
    return envelope;
}

pub const Stats = struct {
    requests_sent: usize = 0,
    notifications_sent: usize = 0,
    frames_read: usize = 0,
    notifications_skipped: usize = 0,
    server_requests_skipped: usize = 0,
    foreign_responses_skipped: usize = 0,
};

pub const Connection = struct {
    stream: Stream = unwiredStream(),
    frames: FrameReader,
    next_id: i64 = 1,
    poison: ?TransportError = null,
    stats: Stats = .{},

    initialized: bool = false,
    home_verified: bool = false,

    pub fn init(storage: []u8, stream: Stream) Connection {
        return .{ .stream = stream, .frames = .init(storage) };
    }

    pub fn allocateId(self: *Connection) i64 {
        const id = self.next_id;

        self.next_id +%= 1;
        return id;
    }

    pub fn arm(self: *Connection, timeout_ms: u32) void {
        self.stream.arm(timeout_ms);
    }

    pub fn sendRequest(self: *Connection, id: i64, method: []const u8, params: anytype, buffer: []u8) TransportError!void {
        const line = try encodeRequest(buffer, id, method, params);
        try self.writeFrame(line);
        self.stats.requests_sent += 1;
    }

    pub fn sendNotification(self: *Connection, method: []const u8, params: anytype, buffer: []u8) TransportError!void {
        const line = try encodeNotification(buffer, method, params);
        try self.writeFrame(line);
        self.stats.notifications_sent += 1;
    }

    pub fn writeFrame(self: *Connection, payload: []const u8) TransportError!void {
        if (self.poison) |err| return err;
        if (payload.len > max_request_bytes) return self.poisonWith(error.RequestTooLarge);

        std.debug.assert(std.mem.indexOfScalar(u8, payload, '\n') == null);
        self.stream.write(payload) catch |err| return self.poisonWith(err);
        self.stream.write("\n") catch |err| return self.poisonWith(err);
    }

    pub fn awaitResponse(self: *Connection, id: i64) TransportError![]const u8 {
        if (self.poison) |err| return err;
        var seen: usize = 0;
        while (seen <= max_interleaved_frames) {
            const frame = self.frames.next(self.stream) catch |err| return self.poisonWith(err);
            self.stats.frames_read += 1;
            const envelope = classify(frame) catch |err| return self.poisonWith(err);
            switch (envelope.kind()) {
                .response => {
                    if (envelope.isResponseTo(id)) return frame;
                    self.stats.foreign_responses_skipped += 1;
                },
                .notification => self.stats.notifications_skipped += 1,
                .server_request => self.stats.server_requests_skipped += 1,

                .unrecognized => return self.poisonWith(error.MalformedFrame),
            }
            seen += 1;
        }
        return self.poisonWith(error.TooManyFrames);
    }

    fn poisonWith(self: *Connection, err: TransportError) TransportError {
        if (self.poison == null) self.poison = err;
        return err;
    }
};

pub fn encodeRequest(buffer: []u8, id: i64, method: []const u8, params: anytype) TransportError![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    writeMessage(&writer, id, method, params) catch return error.RequestTooLarge;
    const line = writer.buffered();
    if (line.len > max_request_bytes) return error.RequestTooLarge;
    return line;
}

pub fn encodeNotification(buffer: []u8, method: []const u8, params: anytype) TransportError![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    writeMessage(&writer, null, method, params) catch return error.RequestTooLarge;
    const line = writer.buffered();
    if (line.len > max_request_bytes) return error.RequestTooLarge;
    return line;
}

fn writeMessage(writer: *std.Io.Writer, id: ?i64, method: []const u8, params: anytype) std.Io.Writer.Error!void {
    var stringify: std.json.Stringify = .{ .writer = writer, .options = .{ .emit_null_optional_fields = false } };
    try stringify.beginObject();
    try stringify.objectField("jsonrpc");
    try stringify.write("2.0");
    if (id) |value| {
        try stringify.objectField("id");
        try stringify.write(value);
    }
    try stringify.objectField("method");
    try stringify.write(method);
    try stringify.objectField("params");
    try stringify.write(params);
    try stringify.endObject();
}

pub const codex_home_var = "CODEX_HOME";

pub const EnvVar = struct { name: []const u8, value: []const u8 };

pub const ParentEnv = union(enum) {
    pairs: []const EnvVar,

    map: *const std.process.Environ.Map,
};

pub const EnvError = error{
    InvalidCodexHome,
    InvalidExecutablePath,
    EnvironmentTooLarge,
    OutOfMemory,
};

pub const inherited_allowlist = [_][]const u8{
    "PATH",
    "HOME",
    "TMPDIR",
    "TZ",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "USER",
    "LOGNAME",
};

pub const scrubbed_prefixes = [_][]const u8{
    "CODEX_",
    "OPENAI_",
    "CHATGPT_",
    "ANTHROPIC_",
    "CLAUDE_",
    "AWS_",
    "AZURE_",
    "GOOGLE_",
    "GEMINI_",
    "GH_",
    "GITHUB_",
    "NPM_",
    "HTTP_",
    "HTTPS_",
    "ALL_",
};

pub const scrubbed_names = [_][]const u8{
    "API_KEY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy",
    "NO_PROXY",
    "SSL_CERT_FILE",
    "SSL_CERT_DIR",
    "NODE_OPTIONS",
    "NODE_EXTRA_CA_CERTS",
};

pub fn isScrubbed(name: []const u8) bool {
    for (scrubbed_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    for (scrubbed_names) |scrubbed| {
        if (std.mem.eql(u8, name, scrubbed)) return true;
    }
    return false;
}

pub fn isInheritable(name: []const u8) bool {
    if (isScrubbed(name)) return false;
    for (inherited_allowlist) |allowed| {
        if (std.mem.eql(u8, name, allowed)) return true;
    }
    return false;
}

comptime {
    for (inherited_allowlist) |allowed| {
        if (isScrubbed(allowed)) @compileError("allowlisted variable is also scrubbed: " ++ allowed);
    }
}

pub fn validateCodexHome(codex_home: []const u8) EnvError!void {
    if (codex_home.len == 0 or codex_home.len > max_path_bytes) return error.InvalidCodexHome;
    if (codex_home[0] != '/') return error.InvalidCodexHome;
    if (codex_home.len > 1 and codex_home[codex_home.len - 1] == '/') return error.InvalidCodexHome;
    for (codex_home) |byte| {
        if (byte == 0 or byte == '\n' or byte == '\r' or byte == '=') return error.InvalidCodexHome;
    }
    var components = std.mem.splitScalar(u8, codex_home[1..], '/');
    while (components.next()) |component| {
        if (component.len == 0) return error.InvalidCodexHome;
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidCodexHome;
    }
}

pub fn buildChildEnv(out: *std.process.Environ.Map, parent: ParentEnv, codex_home: []const u8) EnvError!void {
    try validateCodexHome(codex_home);
    switch (parent) {
        .pairs => |pairs| for (pairs) |pair| try copyIfInheritable(out, pair.name, pair.value),
        .map => |map| {
            var it = map.iterator();
            while (it.next()) |entry| try copyIfInheritable(out, entry.key_ptr.*, entry.value_ptr.*);
        },
    }

    if (out.count() >= max_child_env_vars) return error.EnvironmentTooLarge;
    try out.put(codex_home_var, codex_home);
}

pub fn prependExecutableDirectoryToPath(
    out: *std.process.Environ.Map,
    executable: []const u8,
) EnvError!void {
    if (executable.len < 2 or executable[0] != '/' or executable[executable.len - 1] == '/') {
        return error.InvalidExecutablePath;
    }
    for (executable) |byte| {
        if (byte == 0 or byte == '\n' or byte == '\r' or byte == ':' or byte == '=') {
            return error.InvalidExecutablePath;
        }
    }
    const separator = std.mem.lastIndexOfScalar(u8, executable, '/') orelse
        return error.InvalidExecutablePath;
    if (separator == 0) return;
    const directory = executable[0..separator];
    const existing = out.get("PATH") orelse "";
    var components = std.mem.splitScalar(u8, existing, ':');
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, directory)) return;
    }

    const needed = directory.len + if (existing.len == 0) 0 else 1 + existing.len;
    if (needed > max_env_value_bytes) return error.EnvironmentTooLarge;
    var storage: [max_env_value_bytes]u8 = undefined;
    @memcpy(storage[0..directory.len], directory);
    var length = directory.len;
    if (existing.len != 0) {
        storage[length] = ':';
        length += 1;
        @memcpy(storage[length..][0..existing.len], existing);
        length += existing.len;
    }
    try out.put("PATH", storage[0..length]);
}

pub fn prepareProviderChildEnvironment(
    out: *std.process.Environ.Map,
    executable: []const u8,
    helpers_directory: []const u8,
) EnvError!void {
    if (executable.len != 0) try prependExecutableDirectoryToPath(out, executable);
    if (helpers_directory.len != 0) try prependDirectoryToPath(out, helpers_directory);
}

fn prependDirectoryToPath(out: *std.process.Environ.Map, directory: []const u8) EnvError!void {
    if (directory.len < 2 or directory[0] != '/' or directory[directory.len - 1] == '/') {
        return error.InvalidExecutablePath;
    }
    for (directory) |byte| {
        if (byte == 0 or byte == '\n' or byte == '\r' or byte == ':' or byte == '=') {
            return error.InvalidExecutablePath;
        }
    }

    const existing = out.get("PATH") orelse "";
    if (std.mem.eql(u8, existing, directory) or
        (std.mem.startsWith(u8, existing, directory) and existing.len > directory.len and existing[directory.len] == ':'))
    {
        return;
    }

    const needed = directory.len + if (existing.len == 0) 0 else 1 + existing.len;
    if (needed > max_env_value_bytes) return error.EnvironmentTooLarge;
    var storage: [max_env_value_bytes]u8 = undefined;
    @memcpy(storage[0..directory.len], directory);
    var length = directory.len;
    if (existing.len != 0) {
        storage[length] = ':';
        length += 1;
        @memcpy(storage[length..][0..existing.len], existing);
        length += existing.len;
    }
    try out.put("PATH", storage[0..length]);
}

fn copyIfInheritable(out: *std.process.Environ.Map, name: []const u8, value: []const u8) EnvError!void {
    if (!isInheritable(name)) return;
    if (value.len > max_env_value_bytes) return error.EnvironmentTooLarge;
    if (out.count() >= max_child_env_vars) return error.EnvironmentTooLarge;
    try out.put(name, value);
}

pub const ChildOptions = struct {
    argv: []const []const u8,

    environ: *const std.process.Environ.Map,
    cwd: std.process.Child.Cwd = .inherit,
};

pub const ChildTransport = struct {
    io: std.Io,
    child: std.process.Child,

    deadline: ?std.Io.Clock.Timestamp = null,
    closed: bool = false,

    const vtable: Stream.VTable = .{ .arm = armStream, .read = readStream, .write = writeStream };

    pub fn spawn(io: std.Io, options: ChildOptions) TransportError!ChildTransport {
        if (options.argv.len == 0) return error.SpawnFailed;
        const child = std.process.spawn(io, .{
            .argv = options.argv,
            .environ_map = options.environ,
            .cwd = options.cwd,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
        }) catch return error.SpawnFailed;
        return .{ .io = io, .child = child };
    }

    pub fn stream(self: *ChildTransport) Stream {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn close(self: *ChildTransport) void {
        if (self.closed) return;
        self.closed = true;
        if (self.child.stdin) |stdin| {
            stdin.close(self.io);
            self.child.stdin = null;
        }
        if (self.child.id == null) return;
        self.child.kill(self.io);
    }

    fn armStream(context: *anyopaque, timeout_ms: u32) void {
        const self: *ChildTransport = @ptrCast(@alignCast(context));
        self.deadline = .fromNow(self.io, .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake });
    }

    fn readStream(context: *anyopaque, buffer: []u8) TransportError!usize {
        const self: *ChildTransport = @ptrCast(@alignCast(context));
        const stdout = self.child.stdout orelse return error.EndOfStream;
        const remaining_ms = self.remainingMs() orelse return error.Timeout;
        return runBounded(self.io, remaining_ms, readOnce, .{ self.io, stdout, buffer });
    }

    fn writeStream(context: *anyopaque, bytes: []const u8) TransportError!void {
        const self: *ChildTransport = @ptrCast(@alignCast(context));
        const stdin = self.child.stdin orelse return error.EndOfStream;
        const remaining_ms = self.remainingMs() orelse return error.Timeout;

        _ = try runBounded(self.io, remaining_ms, writeOnce, .{ self.io, stdin, bytes });
    }

    fn remainingMs(self: *ChildTransport) ?u32 {
        const deadline = self.deadline orelse return null;
        const remaining = deadline.durationFromNow(self.io).raw.toMilliseconds();
        if (remaining <= 0) return null;
        return @intCast(@min(remaining, @as(i64, std.math.maxInt(u32))));
    }
};

fn readOnce(io: std.Io, file: std.Io.File, buffer: []u8) TransportError!usize {
    return file.readStreaming(io, &.{buffer}) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
        error.Canceled => error.Canceled,

        else => error.Io,
    };
}

fn writeOnce(io: std.Io, file: std.Io.File, bytes: []const u8) TransportError!usize {
    file.writeStreamingAll(io, bytes) catch return error.Io;
    return bytes.len;
}

pub fn runBounded(
    io: std.Io,
    timeout_ms: u32,
    comptime task: anytype,
    args: std.meta.ArgsTuple(@TypeOf(task)),
) TransportError!usize {
    const Bounded = struct {
        fn run(inner: std.Io, event: *std.Io.Event, inner_args: std.meta.ArgsTuple(@TypeOf(task))) TransportError!usize {
            defer event.set(inner);
            return @call(.auto, task, inner_args);
        }
    };

    var finished: std.Io.Event = .unset;

    var future = io.concurrent(Bounded.run, .{ io, &finished, args }) catch return error.Io;

    const deadline: std.Io.Timeout = (std.Io.Timeout{
        .duration = .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake },
    }).toDeadline(io);

    while (true) {
        if (finished.waitTimeout(io, deadline)) |_| break else |err| switch (err) {
            error.Canceled => {
                _ = future.cancel(io) catch {};
                return error.Canceled;
            },

            error.Timeout => {
                if (finished.isSet()) break;
                if (deadlinePassed(io, deadline)) {
                    _ = future.cancel(io) catch {};
                    return error.Timeout;
                }
            },
        }
    }
    return future.await(io);
}

fn deadlinePassed(io: std.Io, deadline: std.Io.Timeout) bool {
    const timestamp = switch (deadline) {
        .deadline => |value| value,
        else => return false,
    };
    return timestamp.durationFromNow(io).raw.nanoseconds <= 0;
}

pub const FakeStream = struct {
    pub const max_written_bytes: usize = 8 * 1024;

    pub const Chunk = union(enum) {
        bytes: []const u8,

        empty,
        failure: TransportError,
    };

    chunks: []const Chunk = &.{},
    chunk_index: usize = 0,
    chunk_offset: usize = 0,

    exhausted: TransportError = error.EndOfStream,

    written: [max_written_bytes]u8 = @splat(0),
    written_len: usize = 0,
    write_failure: ?TransportError = null,

    arm_count: usize = 0,
    last_timeout_ms: u32 = 0,
    read_count: usize = 0,

    const vtable: Stream.VTable = .{ .arm = arm, .read = read, .write = write };

    pub fn stream(self: *FakeStream) Stream {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn writtenBytes(self: *const FakeStream) []const u8 {
        return self.written[0..self.written_len];
    }

    pub fn writtenFrames(self: *const FakeStream) std.mem.SplitIterator(u8, .scalar) {
        return std.mem.splitScalar(u8, self.writtenBytes(), '\n');
    }

    fn arm(context: *anyopaque, timeout_ms: u32) void {
        const self: *FakeStream = @ptrCast(@alignCast(context));
        self.arm_count += 1;
        self.last_timeout_ms = timeout_ms;
    }

    fn read(context: *anyopaque, buffer: []u8) TransportError!usize {
        const self: *FakeStream = @ptrCast(@alignCast(context));
        self.read_count += 1;
        if (self.chunk_index >= self.chunks.len) return self.exhausted;
        switch (self.chunks[self.chunk_index]) {
            .failure => |err| {
                self.chunk_index += 1;
                return err;
            },
            .empty => {
                self.chunk_index += 1;
                return 0;
            },
            .bytes => |bytes| {
                const rest = bytes[self.chunk_offset..];
                const count = @min(rest.len, buffer.len);
                @memcpy(buffer[0..count], rest[0..count]);
                self.chunk_offset += count;
                if (self.chunk_offset == bytes.len) {
                    self.chunk_index += 1;
                    self.chunk_offset = 0;
                }
                return count;
            },
        }
    }

    fn write(context: *anyopaque, bytes: []const u8) TransportError!void {
        const self: *FakeStream = @ptrCast(@alignCast(context));
        if (self.write_failure) |err| return err;
        if (bytes.len > max_written_bytes - self.written_len) return error.Io;
        @memcpy(self.written[self.written_len..][0..bytes.len], bytes);
        self.written_len += bytes.len;
    }
};

pub const FakeChildLifecycle = struct {
    stdin_closes: usize = 0,
    kills: usize = 0,
    closed: bool = false,

    pub fn close(self: *FakeChildLifecycle) void {
        if (self.closed) return;
        self.closed = true;
        self.stdin_closes += 1;
        self.kills += 1;
    }

    pub fn reapedExactlyOnce(self: FakeChildLifecycle) bool {
        return self.closed and self.stdin_closes == 1 and self.kills == 1;
    }
};
