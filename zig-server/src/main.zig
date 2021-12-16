const std = @import("std");
const http = @import("http");
const net = std.net;
const Allocator = std.mem.Allocator;

const resource_paths = [_][]const u8{
    "dist/bundle.js",
    "styles/main.css",
    "assets/favicon.ico",
    "dist/wasm/bin/night-math.wasm",
};

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

const star_data = @embedFile("../../server/star_data.bin");
const const_data = @embedFile("../../server/const_data.bin");

const RequestHandler = fn (*Allocator, http.HttpRequest) anyerror!http.HttpResponse;
const route_handlers = std.ComptimeStringMap(RequestHandler, .{
    .{ "/", handleIndex },
    .{ "/stars", handleStars },
    .{ "/constellations", handleConstellations },
    .{ "/constellations/meta", handleConstellationMetadata },
});

pub fn main() anyerror!void {
    const port = 8080;
    var localhost = try net.Address.parseIp("0.0.0.0", port);

    var server = net.StreamServer.init(.{});
    defer server.deinit();

    try server.listen(localhost);

    std.log.info("Listening on port {}", .{ port });

    while (true) {
        var connection = try server.accept();
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var conn_thread = try std.Thread.spawn(.{}, handleConnection, .{&arena.allocator, connection});
        defer {
            conn_thread.join();
            arena.deinit();
        }
    }
    
}

fn handleConnection(allocator: *Allocator, connection: net.StreamServer.Connection) !void {
    defer connection.stream.close();

    var timer = std.time.Timer.start() catch unreachable;

    const start_ts = timer.read();
    
    var cwd = std.fs.cwd();
    var request_writer = std.ArrayList(u8).init(allocator);
    
    var reader = connection.stream.reader();
    var writer = connection.stream.writer();

    var request_buffer: [150]u8 = undefined;

    var bytes_read: usize = try reader.read(request_buffer[0..]);
    while (bytes_read > 0) {
        try request_writer.writer().writeAll(request_buffer[0..bytes_read]);

        if (bytes_read < request_buffer.len) break;

        bytes_read = try reader.read(request_buffer[0..]);
    }

    var request = http.HttpRequest{ .data = request_writer.items };
    defer {
        const end_ts = timer.read();
        const uri = request.uri() orelse "/";
        std.log.info("Thread {}: Handling request for {s} took {d:.6}ms", .{std.Thread.getCurrentId(), uri, (@intToFloat(f64, end_ts) - @intToFloat(f64, start_ts)) / std.time.ns_per_ms});
    }

    if (route_handlers.get(request.uri() orelse "/")) |handler| {
        var response = handler(allocator, request) catch http.HttpResponse.initStatus(allocator, .internal_server_error);
        try response.write(writer);
    } else {
        const uri = request.uri() orelse {
            var response = http.HttpResponse.initStatus(allocator, .bad_request);
            try response.write(writer);
            return;
        };
        for (resource_paths) |resource_path| {
            if (std.mem.endsWith(u8, uri, resource_path)) {
                var path = try std.fmt.allocPrint(allocator, "../web/{s}", .{ resource_path });
                var resource = try cwd.openFile(path, .{});
                defer resource.close();

                var resource_data = try resource.readToEndAlloc(allocator, std.math.maxInt(usize));
                
                var response = http.HttpResponse.init(allocator);

                const content_type = getContentType(resource_path).?;
                try response.header("Content-Length", resource_data.len);
                try response.header("Content-Type", content_type);

                response.body = resource_data;

                try response.write(writer);
            }
        }

        var response = http.HttpResponse.initStatus(allocator, .not_found);
        try response.write(writer);
    }
}

fn handleIndex(allocator: *Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    const cwd = std.fs.cwd();
    var index_file = try cwd.openFile("../web/index.html", .{});
    defer index_file.close();

    const index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    
    var response = http.HttpResponse.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "text/html");
    try response.header("Content-Length", index_data.len);
    response.body = index_data;

    return response;
}

fn handleStars(allocator: *Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    var response = http.HttpResponse.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", star_data.len);
    response.body = star_data;

    return response;
}

fn handleConstellations(allocator: *Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    var response = http.HttpResponse.init(allocator);
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", const_data.len);
    response.body = const_data;
    return response;
}

fn handleConstellationMetadata(allocator: *Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    return http.HttpResponse.initStatus(allocator, .not_found);
}