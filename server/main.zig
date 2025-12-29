const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

pub const log_level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};
pub const log = std.log.scoped(.night_server);

const StaticFile = struct {
    uri_path: []const u8,
    file_name: []const u8,

    fn sendFile(static_file: *StaticFile, io: Io, writer: *Io.Writer) !void {
        var file = try Io.Dir.cwd().openFile(io, static_file.file_name, .{});
        defer file.close(io);

        var reader = file.reader(io, &.{});

        _ = try reader.interface.streamRemaining(writer);
    }

    fn pathMatches(static_file: StaticFile, path: []const u8) bool {
        const self_start: usize = if (std.mem.startsWith(u8, static_file.uri_path, "/")) 1 else 0;
        const path_start: usize = if (std.mem.startsWith(u8, path, "/")) 1 else 0;

        return std.mem.eql(u8, static_file.uri_path[self_start..], path[path_start..]);
    }

    fn contentSize(static_file: StaticFile, io: Io) !usize {
        const stat = try Io.Dir.cwd().statFile(io, static_file.file_name, .{});
        return @intCast(stat.size);
    }
};

var is_server_running = true;

fn ctrlCHandlerWindows(signal: u32) callconv(.c) c_int {
    switch (signal) {
        std.os.windows.CTRL_C_EVENT => {
            log.info("ctrl-c pressed", .{});
            is_server_running = false;
            return std.os.windows.FALSE;
        },
        else => return std.os.windows.FALSE,
    }
}

fn ctrlCHandlerLinux(_: c_int) callconv(.c) void {
    is_server_running = false;
}

var static_files = [_]StaticFile{
    .{ .file_name = "web/index.html", .uri_path = "" },
    .{ .file_name = "zig-out/const_meta.json", .uri_path = "constellations/meta" },
    .{ .file_name = "web/styles/main.css", .uri_path = "styles/main.css" },
    .{ .file_name = "web/assets/favicon.ico", .uri_path = "assets/favicon.ico" },
    .{ .file_name = "dist/bundle.js", .uri_path = "bundle.js" },
    .{ .file_name = "dist/bundle.js.map", .uri_path = "bundle.js.map" },
    .{ .file_name = "dist/nightsky_render.wasm", .uri_path = "nightsky_render.wasm" },
};

const TaskTypes = enum { accept, handle };
const Task = union(TaskTypes) {
    accept: net.Server.AcceptError!net.Stream,
    handle: void,
};

pub fn main() !void {
    switch (builtin.os.tag) {
        .windows => try std.os.windows.SetConsoleCtrlHandler(ctrlCHandlerWindows, true),
        else => try std.os.sigaction(
            std.os.SIG.INT,
            &.{
                .handler = .{ .handler = ctrlCHandlerLinux },
                .mask = std.mem.zeroes([32]u32),
                .flags = 0,
            },
            null,
        ),
    }

    const port = 8080;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    const allocator = gpa.allocator();

    var io_threaded: std.Io.Threaded = .init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var localhost = net.IpAddress.parse("0.0.0.0", port) catch @panic("Could not parse listening address.");
    var server = try localhost.listen(io, .{});
    defer server.deinit(io);

    const task_buffer = try allocator.alloc(Task, try std.Thread.getCpuCount());
    defer allocator.free(task_buffer);

    var select: Io.Select(Task) = .init(io, task_buffer);
    defer select.cancel();

    log.info("Listening on port {}", .{port});
    log.debug("Build is single threaded: {}", .{builtin.single_threaded});

    select.async(.accept, net.Server.accept, .{ &server, io });
    while (is_server_running) {
        switch (try select.wait()) {
            .accept => |result| if (result) |stream| {
                select.async(.handle, handleRequest, .{ io, stream });
                select.async(.accept, net.Server.accept, .{ &server, io });
            } else |_| continue,
            .handle => {},
        }
    }

    log.info("Shutting down server...", .{});
}

fn handleRequest(io: Io, stream: net.Stream) void {
    defer stream.close(io);

    var request_buffer: [4096]u8 = undefined;
    var request_reader = stream.reader(io, &request_buffer);
    var request_writer = stream.writer(io, &.{});
    var server: std.http.Server = .init(&request_reader.interface, &request_writer.interface);

    var request = server.receiveHead() catch return;

    handleRequestError(io, &request) catch |err| {
        const status: std.http.Status = switch (err) {
            error.not_found => .not_found,
            error.unexpected => .internal_server_error,
        };

        request.respond("", .{ .status = status }) catch {};
    };
}

const RequestError = error{ not_found, unexpected };
fn handleRequestError(io: Io, request: *std.http.Server.Request) RequestError!void {
    const request_path = request.head.target;

    log.info("Handling request {s}", .{request_path});

    for (&static_files) |*file| {
        if (file.pathMatches(request_path)) {
            serveStaticFile(io, request, file) catch return error.unexpected;
        }
    }

    return error.not_found;
}

fn serveStaticFile(io: Io, request: *std.http.Server.Request, static_file: *StaticFile) !void {
    var write_buf: [1024]u8 = undefined;
    var body_writer = try request.respondStreaming(&write_buf, .{
        .content_length = static_file.contentSize(io) catch 0,
        .respond_options = .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = getMimeType(static_file.file_name) },
            },
        },
    });

    try static_file.sendFile(io, &body_writer.writer);
    try body_writer.end();
}

fn getMimeType(file_name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, file_name, ".css")) {
        return "text/css";
    } else if (std.mem.endsWith(u8, file_name, ".wasm")) {
        return "application/wasm";
    } else if (std.mem.endsWith(u8, file_name, ".js")) {
        return "application/javascript";
    } else if (std.mem.endsWith(u8, file_name, ".ico")) {
        return "image/png";
    } else if (std.mem.endsWith(u8, file_name, ".html")) {
        return "text/html";
    } else if (std.mem.endsWith(u8, file_name, ".json")) {
        return "application/json";
    } else {
        return "text/plain";
    }
}
