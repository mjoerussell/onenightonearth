const std = @import("std");
const builtin = @import("builtin");
const http = @import("http");
const net = std.net;
const Allocator = std.mem.Allocator;

const Server = @import("server.zig").Server;
const client_lib = @import("client.zig");
const CommonClient = client_lib.Client;
const NetworkLoop = client_lib.NetworkLoop;

const is_windows = builtin.os.tag == .windows;

const Client = struct {
    const Connection = if (is_windows) std.os.socket_t else net.StreamServer.Connection;

    common_client: CommonClient,
    handle_frame: *@Frame(Client.handle) = undefined,
    arena: std.heap.ArenaAllocator,
    connected: bool = false,

    pub usingnamespace if (is_windows) struct {
        pub fn init(allocator: Allocator, loop: *NetworkLoop, conn: Connection) !Client {
            return Client{
                .common_client = try CommonClient.init(loop, conn),
                .arena = std.heap.ArenaAllocator.init(allocator),
            };
        }
    } else struct {
        pub fn init(allocator: Allocator, loop: *NetworkLoop, conn: Connection) !Client{
            _ = loop;
            return Client{
                .common_client = CommonClient.init(conn),
                .arena = std.heap.ArenaAllocator.init(allocator),
            };
        }
    };

    fn close(client: *Client) void {
        if (is_windows) {
            client.common_client.deinit();
        } else {
            client.common_client.close();
        }
        client.arena.deinit();
        client.connected = false;
    }

    fn handle(client: *Client, file_map: *std.StringHashMap([]const u8)) !void {   
        defer client.close();

        var timer = std.time.Timer.start() catch unreachable;

        const start_ts = timer.read();

        const allocator = client.arena.allocator();
        
        // var cwd = std.fs.cwd();
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

            var available_resource_iter = file_map.keyIterator();
            while (available_resource_iter.next()) |resource_path| {
                if (std.mem.endsWith(u8, uri, resource_path.*)) {
                    var resource = file_map.get(resource_path.*).?;
                    var response = http.HttpResponse.init(allocator);

                    const content_type = getContentType(resource_path.*).?;
                    try response.header("Content-Length", resource.len);
                    try response.header("Content-Type", content_type);

                    response.body = resource;

                    try response.write(writer);
                    return;
                }
            }

            std.log.warn("Client tried to get resource '{s}', which could not be found", .{uri});

            var response = http.HttpResponse.initStatus(allocator, .not_found);
            try response.write(writer);
        }
    }
    
};

// Only use std's evented io on non-windows targets
pub const io_mode = if (is_windows) .blocking else .evented;

const resource_paths = [_][]const u8{
    "dist/bundle.js",
    "styles/main.css",
    "assets/favicon.ico",
    "dist/wasm/bin/night-math.wasm",
};

const resource_path_rel = blk: {
    var paths: [resource_paths.len][]const u8 = undefined;
    for (paths) |*p, i| {
        p.* = "../web/" ++ resource_paths[i];
    }
    break :blk paths;
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

const RequestHandler = fn (Allocator, http.HttpRequest) anyerror!http.HttpResponse;
const route_handlers = std.ComptimeStringMap(RequestHandler, .{
    .{ "/", handleIndex },
    .{ "/stars", handleStars },
    .{ "/constellations", handleConstellations },
    .{ "/constellations/meta", handleConstellationMetadata },
});

const OneNightServer = struct {
    server: Server,
    net_loop: NetworkLoop = undefined,
    timer: std.time.Timer,

    running: bool = false,
    last_connection: ?u64 = null,

    cleanup_thread: std.Thread,

    clients: std.ArrayList(*Client),
    client_mutex: std.Thread.Mutex,

    static_file_map: std.StringHashMap([]const u8),

    fn init(one_night: *OneNightServer, allocator: Allocator, address: std.net.Address) !void {
        one_night.server = Server.init(.{});
        try one_night.server.listen(address);
        errdefer one_night.server.deinit();

        one_night.timer = std.time.Timer.start() catch unreachable;

        if (is_windows) {
            try one_night.net_loop.init(allocator);
        }

        one_night.clients = std.ArrayList(*Client).init(allocator);
        one_night.running = true;
        one_night.client_mutex = .{};

        const cwd = std.fs.cwd();
        one_night.static_file_map = std.StringHashMap([]const u8).init(allocator);
        for (resource_paths) |path, path_index| {
            var file = try cwd.openFile(resource_path_rel[path_index], .{});
            defer file.close();

            var file_content = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
            try one_night.static_file_map.putNoClobber(path, file_content);
        }

        one_night.cleanup_thread = try std.Thread.spawn(.{}, OneNightServer.cleanup, .{one_night, allocator});
    }

    fn deinit(server: *OneNightServer, allocator: Allocator) void {
        server.running = false;
        for (server.clients.items) |client| {
            allocator.destroy(client.handle_frame);
            allocator.destroy(client);
        }
        server.clients.deinit();
        if (is_windows) {
            server.net_loop.deinit();
        }

        server.server.deinit();
        server.cleanup_thread.join();
    }

    fn accept(server: *OneNightServer, allocator: Allocator) !void {
        var connection = try server.server.accept(); 
        server.last_connection = server.timer.read();

        var client = try allocator.create(Client);
        client.* = try Client.init(allocator, &server.net_loop, connection);
        client.handle_frame = try allocator.create(@Frame(Client.handle));
        client.handle_frame.* = async client.handle(&server.static_file_map);
        client.connected = true;

        server.client_mutex.lock();
        defer server.client_mutex.unlock();
        try server.clients.append(client);
    }

    fn cleanup(server: *OneNightServer, allocator: Allocator) void {
        const cleanup_interval = 1000 * std.time.ns_per_ms;
        while (server.running) {
            const last_connection = server.last_connection orelse continue;

            if (server.timer.read() - last_connection >= cleanup_interval) {
                // Clean up old clients if it's been longer than the specified time since there's been
                // a connection
                server.client_mutex.lock();
                defer server.client_mutex.unlock();

                var clients_removed: usize = 0;
                var client_index: usize = 0;
                while (client_index < server.clients.items.len) {
                    var client = server.clients.items[client_index];
                    if (!client.connected) {
                        var client_to_remove = server.clients.swapRemove(client_index);
                        allocator.destroy(client_to_remove.handle_frame);
                        allocator.destroy(client_to_remove);
                        clients_removed += 1;
                    } else {
                        client_index += 1;
                    }
                }

                std.log.debug("Cleaned up {} clients", .{clients_removed});
                server.last_connection = null;
            }
        }
    }
};

pub fn main() anyerror!void {
    const port = 8080;
    var localhost = try net.Address.parseIp("0.0.0.0", port);
    const allocator = std.heap.page_allocator;

    var server: OneNightServer = undefined;
    try server.init(allocator, localhost);
    defer server.deinit(allocator);

    std.log.info("Listening on port {}", .{ port });

    while (true) {
        server.accept(allocator) catch continue;
    }
}

fn handleIndex(allocator: Allocator, request: http.HttpRequest) !http.HttpResponse {
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

fn handleStars(allocator: Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    var response = http.HttpResponse.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", star_data.len);
    response.body = star_data;

    return response;
}

fn handleConstellations(allocator: Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    var response = http.HttpResponse.init(allocator);
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", const_data.len);
    response.body = const_data;
    return response;
}

fn handleConstellationMetadata(allocator: Allocator, request: http.HttpRequest) !http.HttpResponse {
    _ = request;
    const cwd = std.fs.cwd();
    var index_file = try cwd.openFile("../web/const_meta.json", .{});
    defer index_file.close();

    const index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    
    var response = http.HttpResponse.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/json");
    try response.header("Content-Length", index_data.len);
    response.body = index_data;

    return response;
}