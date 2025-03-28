const std = @import("std");

const vendor_dir = "vendor/";

pub fn build(b: *std.Build) !void {
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
    const use_vendored_deps = b.option(bool, "use-vendor", "Use vendored versions of listed dependencies (put dependencies under a vendor/ directory)") orelse false;

    const default_linux_target = try std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux" });

    const exe = b.addExecutable(.{
        .name = "zig-server",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .optimize = mode,
        .target = if (target_linux) b.resolveTargetQuery(default_linux_target) else target,
        .single_threaded = is_single_threaded orelse false,
    });

    const tortie_module = if (use_vendored_deps)
        b.createModule(.{ .root_source_file = .{ .cwd_relative = vendor_dir ++ "tortie/src/tortie.zig" } })
    else
        b.dependency("tortie", .{}).module("tortie");
    exe.root_module.addImport("tortie", tortie_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
