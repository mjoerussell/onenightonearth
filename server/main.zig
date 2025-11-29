const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

var static_files = [_]StaticFile{
    StaticFile.init("web/index.html", .{ .path = "/" }),
    StaticFile.init("zig-out/const_meta.json", .{ .path = "/constellations/meta", .content_type = "application/json" }),
    StaticFile.init("web/styles/main.css", .{ .relative_to = "web" }),
    StaticFile.init("web/assets/favicon.ico", .{ .relative_to = "web" }),
    StaticFile.init("dist/bundle.js", .{ .relative_to = "dist", .compress = true }),
    StaticFile.init("dist/bundle.js.map", .{ .relative_to = "dist", .compress = true }),
    StaticFile.init("dist/wasm/nightsky_render.wasm", .{ .relative_to = "dist/wasm", .compress = true }),
};

pub const log_level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};

pub const log = std.log.scoped(.night_server);

const StaticFile = struct {
    const InitOptions = struct {
        path: ?[]const u8 = null,
        relative_to: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        compress: bool = false,
    };

    path: []const u8,
    file_name: []const u8,
    content: ?[]const u8 = null,
    content_type: []const u8 = "text/plain",
    secure_context: bool = true,
    compress: bool = false,
    is_standalone: bool = false,

    fn init(file_name: []const u8, options: InitOptions) StaticFile {
        var path: []const u8 = undefined;
        if (options.path) |path_override| {
            path = path_override;
        } else if (options.relative_to) |relative_to| {
            const start_index = if (std.mem.startsWith(u8, file_name, relative_to)) relative_to.len else 0;
            path = file_name[start_index..];
        } else {
            path = file_name;
        }

        return StaticFile{
            .path = path,
            .file_name = file_name,
            .content_type = options.content_type orelse getMimeType(file_name),
            .compress = options.compress,
        };
    }

    fn deinit(static_file: *StaticFile, allocator: Allocator) void {
        if (!static_file.is_standalone) return;
        if (static_file.content) |content| {
            allocator.free(content);
        }
    }

    fn loadContent(static_file: *StaticFile, allocator: Allocator, io: Io) ![]const u8 {
        static_file.is_standalone = true;
        static_file.compress = false;

        var file = try Io.Dir.cwd().openFile(io, static_file.file_name, .{});
        defer file.close(io);

        var reader = file.reader(io, &.{});
        const size = try reader.getSize();

        static_file.content = try reader.interface.readAlloc(allocator, @intCast(size));
        return static_file.content.?;
    }

    fn getContent(static_file: *StaticFile, allocator: Allocator, io: Io) ![]const u8 {
        if (static_file.content) |content| {
            if (builtin.mode != .Debug) {
                return content;
            }
        }
        return try static_file.loadContent(allocator, io);
    }
};

var is_server_running = true;

fn ctrlCHandlerWindows(_: u32) callconv(.c) c_int {
    gracefulDeinit();
    return 0;
}

fn ctrlCHandlerLinux(_: c_int) callconv(.c) void {
    gracefulDeinit();
}

fn gracefulDeinit() void {
    is_server_running = false;
}

pub fn main() anyerror!void {
    const port = 8080;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    switch (builtin.os.tag) {
        .windows => try std.os.windows.SetConsoleCtrlHandler(ctrlCHandlerWindows, true),
        else => try std.os.sigaction(std.os.SIG.INT, &.{ .handler = .{ .handler = ctrlCHandlerLinux }, .mask = std.mem.zeroes([32]u32), .flags = 0 }, null),
    }

    const allocator = gpa.allocator();

    var io_threaded: std.Io.Threaded = .init(allocator);
    const io = io_threaded.io();

    var localhost = std.Io.net.IpAddress.parse("0.0.0.0", port) catch @panic("Could not parse listening address.");
    var server = try localhost.listen(io, .{});

    log.info("Listening on port {}", .{port});
    log.debug("Build is single threaded: {}", .{builtin.single_threaded});

    var group: std.Io.Group = .init;
    defer group.cancel(io);

    while (is_server_running) {
        const stream = try server.accept(io);

        group.async(io, handleRequest, .{ allocator, io, stream });
    }
}

fn handleRequest(allocator: Allocator, io: std.Io, stream: std.Io.net.Stream) void {
    defer stream.close(io);

    var request_buffer: [4096]u8 = undefined;
    var request_reader = stream.reader(io, &request_buffer);
    var request_writer = stream.writer(io, &.{});
    var server: std.http.Server = .init(&request_reader.interface, &request_writer.interface);

    var request = server.receiveHead() catch return;
    const request_path = request.head.target;

    log.info("Handling request {s}", .{request_path});

    for (&static_files) |*file| {
        if (std.mem.eql(u8, request_path, file.path)) {
            serveStaticFile(allocator, io, &request, file) catch |err| {
                request.respond(@errorName(err), .{ .status = .internal_server_error }) catch {};
            };
            return;
        }
    }

    request.respond("", .{ .status = .not_found }) catch |err| {
        request.respond(@errorName(err), .{ .status = .internal_server_error }) catch {};
    };
}

fn serveStaticFile(allocator: Allocator, io: Io, request: *std.http.Server.Request, file: *StaticFile) !void {
    const content = try file.getContent(allocator, io);

    log.info("Loaded content for {s}", .{file.path});

    try request.respond(
        content,
        .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = file.content_type },
            },
        },
    );
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
    } else {
        return "text/plain";
    }
}
