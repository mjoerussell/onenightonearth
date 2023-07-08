const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {
    _ = b.addModule("tortie", .{
        .source_file = .{ .path = "src/tortie.zig" },
    });
}
