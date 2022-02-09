const std = @import("std");
const Builder = std.build.Builder;
const Target = std.build.Target;

const ts_generator = @import("generate_interface.zig");

const output_dir = "../web/dist/wasm";
const test_files = [_][]const u8{ "src/star_math.zig", "src/math_utils.zig", "src/render.zig" };

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const default_target = b.standardTargetOptions(.{});

    const lib = b.addSharedLibrary("night-math", "src/main.zig", b.version(0, 0, 0));
    lib.setBuildMode(mode);
    const target = try std.zig.CrossTarget.parse(.{
        .arch_os_abi = "wasm32-freestanding",
        .cpu_features = "generic+simd128"
    });
    lib.setTarget(target);
    lib.setOutputDir(output_dir);
    
    const cwd = std.fs.cwd();
    // If the dir isn't deleted before writing the lib, then it fails with the error 'TooManyParentDirs'
    try cwd.deleteTree(output_dir);

    const ts_gen = b.addExecutable("gen", "generate_interface.zig");
    ts_gen.setBuildMode(.ReleaseSafe);
    ts_gen.setTarget(default_target);
    ts_gen.install();

    const run_generator = ts_gen.run();
    run_generator.step.dependOn(&ts_gen.install_step.?.step);

    const gen_step = b.step("gen-ts", "Generate a .d.ts file for Typescript to consume");
    gen_step.dependOn(&run_generator.step);

    // try ts_generator.generateInterface();

    lib.install();

    const test_step = b.step("test", "Run library tests");
    for (test_files) |file| {
        var tests = b.addTest(file);
        tests.setBuildMode(mode);
        test_step.dependOn(&tests.step);
    }
}
