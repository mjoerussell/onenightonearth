const std = @import("std");
const Builder = std.build.Builder;
const Target = std.build.Target;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = try Target.parse(.{ .arch_os_abi = "wasm32-freestanding" });
    const lib = b.addStaticLibrary("one-math", "src/main.zig");
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();

    var star_math_tests = b.addTest("src/star_math.zig");
    star_math_tests.setBuildMode(mode);

    var math_tests = b.addTest("src/math_utils.zig");
    math_tests.setBuildMode(mode);

    var render_tests = b.addTest("src/render.zig");
    render_tests.setBuildMode(mode);

    var matrix_tests = b.addTest("src/matrix.zig");
    matrix_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    // test_step.dependOn(&main_tests.step);
    test_step.dependOn(&star_math_tests.step);
    test_step.dependOn(&math_tests.step);
    test_step.dependOn(&render_tests.step);
    test_step.dependOn(&matrix_tests.step);
}
