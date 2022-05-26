const std = @import("std");
const builtin = @import("builtin");
const net = std.net;
const Allocator = std.mem.Allocator;

const Server = @import("server.zig").Server;
const client_lib = @import("client.zig");
const CommonClient = client_lib.Client;
const NetworkLoop = client_lib.NetworkLoop;

const OneNightServer = @import("OneNightServer.zig");
const OneNightClient = @import("OneNightClient.zig");

pub fn main() anyerror!void {
    std.log.info("Starting server", .{});

    const port = 8080;
    var localhost = try net.Address.parseIp("0.0.0.0", port);
    const allocator = std.heap.page_allocator;

    var server: OneNightServer = undefined;
    try server.init(allocator, localhost);
    defer server.deinit(allocator);

    std.log.info("Listening on port {}", .{ port });

    while (true) {
        server.accept(allocator) catch {};
        if (builtin.single_threaded) {
            server.net_loop.getCompletion() catch continue;
        }
    }
}