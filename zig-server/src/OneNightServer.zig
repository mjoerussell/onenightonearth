const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const Thread = std.Thread;

const http = @import("http");

const OneNightServer = @This();

const Client = @import("OneNightClient.zig");
const Server = @import("server.zig").Server;
const NetworkLoop = @import("client.zig").NetworkLoop;

const ClientList = std.ArrayList(*Client);
const FileMap = std.StringHashMap([]const u8);

const is_windows = builtin.os.tag == .windows;

server: Server,
net_loop: NetworkLoop = undefined,
timer: Timer,

running: bool = false,
last_connection: ?u64 = null,

cleanup_thread: Thread,

clients: ClientList,
client_mutex: Thread.Mutex,

static_file_map: FileMap,

pub fn init(one_night: *OneNightServer, allocator: Allocator, address: std.net.Address, resource_paths: []const []const u8, resource_path_rel: []const []const u8) !void {
    one_night.server = Server.init(.{});
    try one_night.server.listen(address);
    errdefer one_night.server.deinit();

    one_night.timer = Timer.start() catch unreachable;

    if (is_windows) {
        try one_night.net_loop.init(allocator);
    }

    one_night.clients = ClientList.init(allocator);
    one_night.running = true;
    one_night.client_mutex = .{};

    const cwd = std.fs.cwd();
    one_night.static_file_map = FileMap.init(allocator);
    for (resource_paths) |path, path_index| {
        var file = cwd.openFile(resource_path_rel[path_index], .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.err("Could not open file {s}", .{resource_path_rel[path_index]});
                continue;
            },
            else => {
                std.log.err("Error opening file '{s}': {}", .{resource_path_rel[path_index], err});
                continue;
            }
        };
        defer file.close();

        var file_content = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
        try one_night.static_file_map.putNoClobber(path, file_content);

        std.log.info("Loaded file '{s}'", .{path});
    }

    one_night.cleanup_thread = try std.Thread.spawn(.{}, OneNightServer.cleanup, .{one_night, allocator});
}

pub fn deinit(server: *OneNightServer, allocator: Allocator) void {
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

pub fn accept(server: *OneNightServer, allocator: Allocator) !void {
    var connection = try server.server.accept(); 
    server.last_connection = server.timer.read();

    std.log.debug("Got connection", .{});

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

