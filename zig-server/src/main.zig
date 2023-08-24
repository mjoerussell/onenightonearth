const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const tortie = @import("tortie");
const TortieServer = tortie.TortieServer;
const http = tortie.http;

const allowed_files = [_][]const u8{
    "../web/dist/bundle.js",
    "../web/styles/main.css",
    "../web/assets/favicon.ico",
    "../web/dist/wasm/night-math.wasm",
};

pub const log_level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};

const ServerContext = struct {};

pub fn main() anyerror!void {
    const port = 8080;
    var localhost = try std.net.Address.parseIp("0.0.0.0", port);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var context = ServerContext{};
    var server = try TortieServer(ServerContext).init(allocator, localhost, context, handleRequest);

    std.log.info("Listening on port {}", .{port});
    std.log.debug("Build is single threaded: {}", .{builtin.single_threaded});

    while (true) {
        server.run() catch {};
    }
}

fn handleRequest(client: *tortie.Client, context: ServerContext) !void {
    handleRequestError(client, context) catch |err| {
        const status: tortie.Response.ResponseStatus = if (err == error.NotFound) .not_found else .internal_server_error;
        try client.response.writeStatus(status);
    };
}

fn handleRequestError(client: *tortie.Client, context: ServerContext) !void {
    _ = context;
    const request_path = client.request.getPath() catch blk: {
        std.log.warn("Could not parse path, defaulting to /", .{});
        break :blk "/";
    };

    std.log.info("Handling request {s}", .{request_path});

    if (std.mem.eql(u8, request_path, "/")) {
        try serveStaticFile(client, .{ .file_name = "../web/index.html", .content_type = "text/html" });
    } else if (std.mem.eql(u8, request_path, "/stars")) {
        try serveStaticFile(client, .{ .file_name = "star_data.bin", .content_type = "octet-stream" });
    } else if (std.mem.eql(u8, request_path, "/constellations")) {
        try serveStaticFile(client, .{ .file_name = "const_data.bin", .content_type = "octet-stream" });
    } else if (std.mem.eql(u8, request_path, "/constellations/meta")) {
        try serveStaticFile(client, .{ .file_name = "const_meta.json", .content_type = "application/json" });
    } else {
        inline for (allowed_files) |file_path| {
            if (std.mem.endsWith(u8, file_path, request_path)) {
                const mime_type = getMimeType(file_path);
                try serveStaticFile(client, .{ .file_name = file_path, .content_type = mime_type });
            }
        }
    }
}

const StaticFileOptions = struct {
    file_name: []const u8,
    content_type: []const u8 = "text/plain",
};

const StaticFileError = error{ NotFound, UnknownError };

fn serveStaticFile(client: *tortie.Client, options: StaticFileOptions) StaticFileError!void {
    const cwd = std.fs.cwd();
    var target_file = cwd.openFile(options.file_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return StaticFileError.NotFound,
        else => return StaticFileError.UnknownError,
    };
    defer target_file.close();

    const file_size = blk: {
        const stat = target_file.stat() catch break :blk 0;
        break :blk stat.size;
    };

    client.response.writeStatus(.ok) catch return StaticFileError.UnknownError;
    client.response.writeHeader("Content-Type", options.content_type) catch return StaticFileError.UnknownError;
    client.response.writeHeader("Content-Length", file_size) catch return StaticFileError.UnknownError;

    var buffer: [1024]u8 = undefined;
    while (true) {
        const bytes_read = target_file.read(&buffer) catch break;

        client.response.writeBody(buffer[0..bytes_read]) catch break;
        if (bytes_read < buffer.len) break;
    }
}

fn getMimeType(file_name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, file_name, ".css")) {
        return "text/css";
    } else if (std.mem.endsWith(u8, file_name, ".wasm")) {
        return "application/wasm";
    } else if (std.mem.endsWith(u8, file_name, ".js")) {
        return "application/javascript";
    } else if (std.mem.endsWith(u8, file_name, ".ico")) {
        return "image/vnd.microsoft.icon";
    } else {
        return "text/plain";
    }
}
