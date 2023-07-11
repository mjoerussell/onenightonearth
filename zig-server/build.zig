const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardOptimizeOption(.{});

    const is_single_threaded = b.option(bool, "single-threaded", "Build in single-threaded mode?");
    const target_linux = b.option(bool, "target-linux", "Build for the default linux target instead of the native target") orelse false;

    const default_linux_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "x86_64-linux" });

    const tortie_dep = b.dependency("tortie", .{});

    const exe = b.addExecutable(.{
        .name = "zig-server",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = mode,
        .target = if (target_linux) default_linux_target else target,
    });

    exe.addModule("tortie", tortie_dep.module("tortie"));

    b.installArtifact(exe);

    exe.single_threaded = is_single_threaded orelse false;

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
