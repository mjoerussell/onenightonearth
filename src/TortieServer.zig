const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const TortieServer = @This();

const Client = @import("TortieClient.zig");
const Server = @import("server.zig").Server;
const EventLoop = @import("event_loop.zig").EventLoop;
const FileSource = @import("FileSource.zig");
const Route = @import("Route.zig");

const ClientList = std.ArrayList(*Client);

const has_custom_impl = switch (builtin.os.tag) {
    .windows, .linux => true,
    else => false,
};

server: Server,
event_loop: EventLoop = undefined,
routes: std.ArrayList(Route),

clients: ClientList,

file_source: ?FileSource = null,

/// Starting listening on the given address and initialize other server resources.
pub fn init(tortie: *TortieServer, allocator: Allocator, address: std.net.Address) !void {
    tortie.server = if (has_custom_impl) Server{} else Server.init(.{});
    try tortie.server.listen(address);
    errdefer tortie.server.deinit();

    if (has_custom_impl) {
        try tortie.event_loop.init(allocator, .{ });
    }

    tortie.routes = std.ArrayList(Route).init(allocator);
    tortie.clients = ClientList.init(allocator);
}

pub fn deinit(server: *TortieServer, allocator: Allocator) void {
    for (server.clients.items) |client| {
        allocator.destroy(client.handle_frame);
        allocator.destroy(client);
    }
    server.clients.deinit();
    if (has_custom_impl) {
        server.event_loop.deinit(allocator);
    }

    server.server.deinit();
}

pub fn addRoute(server: *TortieServer, uri: []const u8, handler: Route.Handler) !void { 
    try server.routes.append(.{ .uri = uri, .handler = handler });
}

pub fn run(server: *TortieServer, allocator: Allocator) noreturn {
    while (true) {
        server.accept(allocator) catch {};
        if (builtin.single_threaded) {
            server.event_loop.getCompletion() catch continue;
        }
    }
}

/// Accept a new client connection and add it to the client list. Also starts handling the client request/response
/// process.
pub fn accept(server: *TortieServer, allocator: Allocator) !void {
    // Put the cleanup here at the very end of execution so that it gets run no matter
    // what happens (if there are any errors or not)
    defer server.cleanup(allocator);
    const connection = try server.server.accept();

    std.log.debug("Got connection", .{});

    // Create a new client and start handling its request.
    var client = try Client.init(allocator, &server.event_loop, connection);
    client.run(server.file_source, server.routes.items);

    // Append the client to the server's client list.
    try server.clients.append(client);
}

/// Remove clients that are no longer connected from the client list
fn cleanup(server: *TortieServer, allocator: Allocator) void {
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

