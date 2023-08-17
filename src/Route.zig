const std = @import("std");
const Allocator = std.mem.Allocator;

const http = @import("http");
const FileSource = @import("FileSource.zig");

const Route = @This();

pub const Handler = fn (Allocator, ?FileSource, http.Request) anyerror!http.Response;

uri: []const u8,
handler: Handler,

pub fn matches(route: Route, path: []const u8) bool {
    return std.mem.eql(u8, route.uri, path);
}
