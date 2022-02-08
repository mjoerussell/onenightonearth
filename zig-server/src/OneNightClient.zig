const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const os = std.os;
const net = std.net;
const Timer = std.time.Timer;

const http = @import("http");

const OneNightClient = @This();

const CommonClient = @import("client.zig").Client;
const NetworkLoop = @import("client.zig").NetworkLoop;
const FileSource = @import("FileSource.zig");

const is_windows = builtin.os.tag == .windows;

const Connection = if (is_windows) std.os.socket_t else net.StreamServer.Connection;

const RequestHandler = fn (Allocator, http.Request) anyerror!http.Response;
const route_handlers = std.ComptimeStringMap(RequestHandler, .{
    .{ "/", handleIndex },
    .{ "/stars", handleStars },
    .{ "/constellations", handleConstellations },
    .{ "/constellations/meta", handleConstellationMetadata },
});

const star_data = @embedFile("../star_data.bin");
const const_data = @embedFile("../const_data.bin");

common_client: CommonClient,
handle_frame: *@Frame(OneNightClient.handle) = undefined,
arena: std.heap.ArenaAllocator,
connected: bool = false,

pub fn init(allocator: Allocator, loop: *NetworkLoop, conn: Connection) !OneNightClient {
    const common_client = 
        if (is_windows) try CommonClient.init(loop, conn) 
        else try CommonClient.init(conn);

    if (!is_windows) _ = loop;

    return OneNightClient{ 
        .common_client = common_client,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn close(client: *OneNightClient) void {
    if (is_windows) {
        client.common_client.deinit();
    } else {
        client.common_client.conn.stream.close();
    }
    client.arena.deinit();
    client.connected = false;
}

pub fn handle(client: *OneNightClient, file_source: FileSource) !void {   
    defer client.close();

    var timer = Timer.start() catch unreachable;

    const start_ts = timer.read();

    const allocator = client.arena.allocator();
    
    var request_writer = std.ArrayList(u8).init(allocator);
    
    var reader = client.common_client.reader();
    var writer = client.common_client.writer();

    var request_buffer: [150]u8 = undefined;

    var bytes_read: usize = try reader.read(request_buffer[0..]);
    while (bytes_read > 0) {
        try request_writer.writer().writeAll(request_buffer[0..bytes_read]);

        if (bytes_read < request_buffer.len) break;

        bytes_read = try reader.read(request_buffer[0..]);
    }

    var request = http.Request{ .data = request_writer.items };
    defer {
        const end_ts = timer.read();
        const uri = request.uri() orelse "/";
        std.log.info("Thread {}: Handling request for {s} took {d:.6}ms", .{std.Thread.getCurrentId(), uri, (@intToFloat(f64, end_ts) - @intToFloat(f64, start_ts)) / std.time.ns_per_ms});
    }

    if (route_handlers.get(request.uri() orelse "/")) |handler| {
        var response = handler(allocator, request) catch |err| {
            std.log.err("Error handling request at {s}: {}", .{request.uri().?, err});
            break http.Response.initStatus(allocator, .internal_server_error);
        };
        try response.write(writer);
    } else {
        const uri = request.uri() orelse {
            var response = http.Response.initStatus(allocator, .bad_request);
            try response.write(writer);
            return;
        };

        const file_data = file_source.getFile(allocator, uri) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("Client tried to get file {s}, but it could not be found", .{uri});
                var response = http.Response.initStatus(allocator, .not_found);
                try response.write(writer);
                return;
            },
            else => {
                std.log.err("Error when trying to get file {s}: {}", .{uri, err});
                var response = http.Response.initStatus(allocator, .internal_server_error);
                try response.write(writer);
                return;
            }
        };

        const content_type = getContentType(uri).?;
        
        var response = http.Response.init(allocator);    
        try response.header("Content-Length", file_data.len);
        try response.header("Content-Type", content_type);
        response.body = file_data;

        try response.write(writer);
    }
}

fn getContentType(filename: []const u8) ?[]const u8 {
    if (std.mem.endsWith(u8, filename, ".css")) {
        return "text/css";
    }

    if (std.mem.endsWith(u8, filename, ".html")) {
        return "text/html";
    }

    if (std.mem.endsWith(u8, filename, ".js")) {
        return "application/javascript";
    }

    if (std.mem.endsWith(u8, filename, ".wasm")) {
        return "application/wasm";
    }

    if (std.mem.endsWith(u8, filename, ".ico")) {
        return "image/x-icon";
    }

    return null;
}

fn handleIndex(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    const cwd = std.fs.cwd();
    std.log.info("Reading index.html", .{});
    var index_file = try cwd.openFile("../web/index.html", .{});
    defer index_file.close(); 

    
    const index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    
    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "text/html");
    try response.header("Content-Length", index_data.len);
    response.body = index_data;

    return response;
}

fn handleStars(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", star_data.len);
    response.body = star_data;

    return response;
}

fn handleConstellations(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    var response = http.Response.init(allocator);
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", const_data.len);
    response.body = const_data;
    return response;
}

fn handleConstellationMetadata(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    const cwd = std.fs.cwd();
    var index_file = try cwd.openFile("const_meta.json", .{});
    defer index_file.close();

    const index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    
    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/json");
    try response.header("Content-Length", index_data.len);
    response.body = index_data;

    return response;
}