const std = @import("std");
const Allocator = std.mem.Allocator;

const Route = @This();

uri: []const u8,

pub fn matches(route: Route, path: []const u8) bool {
    return std.mem.eql(u8, route.uri, path);
}
