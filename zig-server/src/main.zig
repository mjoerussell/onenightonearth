const std = @import("std");
const builtin = @import("builtin");
const http = @import("http");
const net = std.net;
const Allocator = std.mem.Allocator;

const Server = @import("server.zig").Server;
const client_lib = @import("client.zig");
const CommonClient = client_lib.Client;
const NetworkLoop = client_lib.NetworkLoop;

const OneNightServer = @import("OneNightServer.zig");
const OneNightClient = @import("OneNightClient.zig");

// @todo In debug mode, don't cache files - re-read them every time they're fetched so that the server
//       doesn't have to be restarted in order to modify them
// @todo In debug mode, periodically check for file modifications to support some kind of hot reloading
// @todo Linux net loop, or at least figure out why async io isn't working inside the contianer

const is_windows = builtin.os.tag == .windows;
// Only use std's evented io on non-windows targets
pub const io_mode = if (is_windows) .blocking else .evented;

const resource_paths = [_][]const u8{
    "dist/bundle.js",
    "styles/main.css",
    "assets/favicon.ico",
    "dist/wasm/night-math.wasm",
};

const resource_path_rel = blk: {
    var paths: [resource_paths.len][]const u8 = undefined;
    for (paths) |*p, i| {
        p.* = "../web/" ++ resource_paths[i];
    }
    break :blk paths;
};

pub fn main() anyerror!void {
    std.log.info("Starting server", .{});

    const port = 8080;
    var localhost = try net.Address.parseIp("0.0.0.0", port);
    const allocator = std.heap.page_allocator;

    var server: OneNightServer = undefined;
    try server.init(allocator, localhost, resource_paths[0..], resource_path_rel[0..]);
    defer server.deinit(allocator);

    std.log.info("Listening on port {}", .{ port });

    while (true) {
        server.accept(allocator) catch continue;
    }
}