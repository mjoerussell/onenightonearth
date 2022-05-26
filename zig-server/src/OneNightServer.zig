const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const OneNightServer = @This();

const Client = @import("OneNightClient.zig");
const Server = @import("server.zig").Server;
const NetworkLoop = @import("client.zig").NetworkLoop;
const FileSource = @import("FileSource.zig");

const ClientList = std.ArrayList(*Client);

server: Server,
net_loop: NetworkLoop = undefined,

clients: ClientList,

file_source: FileSource,

/// Starting listening on the given address and initialize other server resources.
pub fn init(one_night: *OneNightServer, allocator: Allocator, address: std.net.Address) !void {
    one_night.server = Server.init(.{});
    try one_night.server.listen(address);
    errdefer one_night.server.deinit();

    if (builtin.os.tag == .windows or builtin.os.tag == .linux) {
        try one_night.net_loop.init(allocator, .{ .extra_thread_count = 0 });
    }

    one_night.clients = ClientList.init(allocator);
    one_night.file_source = try FileSource.init(allocator);
}

pub fn deinit(server: *OneNightServer, allocator: Allocator) void {
    for (server.clients.items) |client| {
        allocator.destroy(client.handle_frame);
        allocator.destroy(client);
    }
    server.clients.deinit();
    if (builtin.os.tag == .windows or builtin.os.tag == .linux) {
        server.net_loop.deinit();
    }

    server.server.deinit();
}

/// Accept a new client connection and add it to the client list. Also starts handling the client request/response
/// process.
pub fn accept(server: *OneNightServer, allocator: Allocator) !void {
    // Put the cleanup here at the very end of execution so that it gets run no matter
    // what happens (if there are any errors or not)
    defer server.cleanup(allocator);
    var connection = try server.server.accept();

    // Linux gets a StreamServer.Connection from accept(), but the LinuxClient expects a sockfd
    // init argument. In that case we should get it from the Connection, but in other cases (macos)
    // just use the Connection like before (it will go to DefaultClient).
    var sock = if (builtin.os.tag == .linux) connection.stream.handle else connection;

    // Create a new client and start handling its request.
    var client = try Client.init(allocator, &server.net_loop, sock);
    client.run(server.file_source);

    // Append the client to the server's client list.
    try server.clients.append(client);
}

/// Background "process" for cleaning up expired clients. Whenever the server has gone > 1sec without accepting a new connection
/// this will remove and destroy all of the clients that have disconnected.
fn cleanup(server: *OneNightServer, allocator: Allocator) void {
    var client_index: usize = 0;
    while (client_index < server.clients.items.len) {
        var client = server.clients.items[client_index];
        if (!@atomicLoad(bool, &client.connected, .SeqCst)) {
            var client_to_remove = server.clients.swapRemove(client_index);
            allocator.destroy(client_to_remove.handle_frame);
            allocator.destroy(client_to_remove);
        } else {
            // Only increment the client array index if the current client wasn't removed. Otherwise clients
            // will be skipped because we're using swapRemove
            client_index += 1;
        }
    }
}

