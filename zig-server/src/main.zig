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

// @todo In debug mode, periodically check for file modifications to support some kind of hot reloading
// @todo Linux net loop, or at least figure out why async io isn't working inside the contianer

const is_windows = builtin.os.tag == .windows;
// Only use std's evented io on non-windows targets
pub const io_mode = if (is_windows) .blocking else .evented;

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
        server.accept(allocator) catch continue;
    }
}