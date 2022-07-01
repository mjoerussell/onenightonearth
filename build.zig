const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn link(exe: *std.build.LibExeObjStep, allocator: Allocator, package_path: []const u8) !void {
    const lib_path = try std.fmt.allocPrint(allocator, "{s}/src/lib.zig", .{package_path});
    defer allocator.free(lib_path);
    
    const http_lib_path = try std.fmt.allocPrint(allocator, "{s}/http/src/lib.zig", .{package_path});
    defer allocator.free(http_lib_path);

    exe.addPackage(std.build.Pkg{
        .name = "tortie",
        .source = std.build.FileSource.relative(lib_path),
        .dependencies = &[_]std.build.Pkg{ .{
            .name = "http",
            .source = std.build.FileSource.relative(http_lib_path),
        }},
    });
}

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("tortie", "src/main.zig");
    
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    exe.addPackagePath("http", "http/src/lib.zig");

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
