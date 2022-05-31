const std = @import("std");
const builtin = @import("builtin");

const OneNightServer = @import("OneNightServer.zig");

pub fn main() anyerror!void {
    std.log.info("Starting server", .{});

    const port = 8080;
    var localhost = try std.net.Address.parseIp("0.0.0.0", port);
    const allocator = std.heap.page_allocator;

    var server: OneNightServer = undefined;
    try server.init(allocator, localhost);
    defer server.deinit(allocator);

    std.log.info("Listening on port {}", .{ port });
    std.log.info("Build is single threaded: {}", .{builtin.single_threaded});

    while (true) {
        server.accept(allocator) catch {};
        if (builtin.single_threaded) {
            server.event_loop.getCompletion() catch continue;
        }
    }
}