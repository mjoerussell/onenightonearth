const std = @import("std");
const builtin = @import("builtin");

const Server = @import("TortieServer.zig");

pub const log_level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};

pub fn main() anyerror!void {
    const port = 3000;
    var localhost = try std.net.Address.parseIp("0.0.0.0", port);
    const allocator = std.heap.page_allocator;

    var server: Server = undefined;
    try server.init(allocator, localhost);
    defer server.deinit(allocator);

    std.log.info("Listening on port {}", .{ port });
    std.log.debug("Build is single threaded: {}", .{builtin.single_threaded});

    while (true) {
        server.accept(allocator) catch {};
        if (builtin.single_threaded) {
            server.event_loop.getCompletion() catch continue;
        }
    }
}