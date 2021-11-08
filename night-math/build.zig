const std = @import("std");
const Builder = std.build.Builder;
const Target = std.build.Target;

const test_files = [_][]const u8{ "src/star_math.zig", "src/math_utils.zig", "src/render.zig" };

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("night-math", "src/main.zig", b.version(0, 0, 0));
    lib.setBuildMode(mode);
    const target = try std.zig.CrossTarget.parse(.{
        .arch_os_abi = "wasm32-freestanding",
        .cpu_features = "generic+simd128"
    });
    lib.setTarget(target);
    lib.setOutputDir("../web/dist/wasm/bin");
    lib.install();

    const test_step = b.step("test", "Run library tests");
    for (test_files) |file| {
        var tests = b.addTest(file);
        tests.setBuildMode(mode);
        test_step.dependOn(&tests.step);
    }
}
