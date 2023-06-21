const std = @import("std");
const build = std.build;
const Build = build.Build;

pub fn build(b: *std.build.Build) !void {
    _ = b.addModule("tortie", .{
        .source_file = .{ .path = "src/tortie.zig" },
    });
}
