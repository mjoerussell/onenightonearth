const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const Thread = std.Thread;

const OneNightServer = @This();

const Client = @import("OneNightClient.zig");
const Server = @import("server.zig").Server;
const NetworkLoop = @import("client.zig").NetworkLoop;
const FileSource = @import("FileSource.zig");

const ClientList = std.ArrayList(*Client);

const is_windows = builtin.os.tag == .windows;

server: Server,
net_loop: NetworkLoop = undefined,
timer: Timer,

running: bool = false,
last_connection: ?u64 = null,

cleanup_thread: Thread,

clients: ClientList,
client_mutex: Thread.Mutex,

file_source: FileSource,

pub fn init(one_night: *OneNightServer, allocator: Allocator, address: std.net.Address) !void {
    one_night.server = Server.init(.{});
    try one_night.server.listen(address);
    errdefer one_night.server.deinit();

    one_night.timer = Timer.start() catch unreachable;

    if (builtin.os.tag == .windows or builtin.os.tag == .linux) {
        try one_night.net_loop.init(allocator);
    }

    one_night.clients = ClientList.init(allocator);
    one_night.running = true;
    one_night.client_mutex = .{};
    one_night.file_source = try FileSource.init(allocator);

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

    // Linux gets a StreamServer.Connection from accept(), but the LinuxClient expects a sockfd
    // init argument. In that case we should get it from the Connection, but in other cases (macos)
    // just use the Connection like before (it will go to DefaultClient).
    var sock = if (builtin.os.tag == .linux) connection.stream.handle else connection;

    // Create a new client and start handling its request. Store the suspended frame in handle_frame
    // for later reference
    var client = try allocator.create(Client);
    client.* = try Client.init(allocator, &server.net_loop, sock);
    client.handle_frame = try allocator.create(@Frame(Client.handle));
    client.handle_frame.* = async client.handle(server.file_source);

    client.connected = true;

    server.client_mutex.lock();
    defer server.client_mutex.unlock();

    // Append the client to the server's client list.
    try server.clients.append(client);
}

/// Background "process" for cleaning up expired clients. Whenever the server has gone > 1sec without accepting a new connection
/// this will remove and destroy all of the clients that have disconnected.
fn cleanup(server: *OneNightServer, allocator: Allocator) void {
    const cleanup_interval = 1000 * std.time.ns_per_ms;
    while (server.running) {
        // If no clients have connected since the last cleanup then do nothing. Otherwise
        // get the timestamp of the last connection.
        const last_connection = server.last_connection orelse continue;

        if (server.timer.read() - last_connection >= cleanup_interval) {
            // Clean up old clients if it's been longer than the specified time since there's been
            // a connection
            // Prevent new clients from being added until this cleanup is done
            // Also don't start the cleanup if a new client is being added
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
                    // Only increment the client array index if the current client wasn't removed. Otherwise clients
                    // will be skipped because we're using swapRemove
                    client_index += 1;
                }
            }

            std.log.debug("Cleaned up {} clients", .{clients_removed});
            server.last_connection = null;
        }
    }
}

