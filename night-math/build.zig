const std = @import("std");
const Builder = std.build.Builder;
const Target = std.build.Target;

const output_dir = "../../web/dist/wasm";
const test_files = [_][]const u8{ "src/star_math.zig", "src/math_utils.zig", "src/render.zig" };

pub fn build(b: *Builder) !void {
    const mode = b.standardOptimizeOption(.{});
    const default_target = b.standardTargetOptions(.{});

    const skip_ts_gen = b.option(bool, "no-gen", "Skip generating a .ts file containing type definitions for exported functions and extern-compatible types.") orelse false;

    const lib = b.addSharedLibrary(.{
        .name = "night-math",
        .root_source_file = std.build.FileSource{ .path = "src/main.zig" },
        .target = try std.zig.CrossTarget.parse(.{
            .arch_os_abi = "wasm32-freestanding",
            .cpu_features = "generic+simd128",
        }),
        .optimize = mode,
    });

    lib.import_symbols = true;
    lib.rdynamic = true;

    const lib_install_artifact = b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = output_dir } } });
    b.getInstallStep().dependOn(&lib_install_artifact.step);

    if (!skip_ts_gen) {
        const ts_gen = b.addExecutable(.{
            .name = "gen",
            .root_source_file = std.build.FileSource{ .path = "generate_interface.zig" },
            .optimize = .ReleaseSafe,
            .target = default_target,
        });

        const run_generator = b.addRunArtifact(ts_gen);
        run_generator.step.dependOn(&ts_gen.step);
        run_generator.has_side_effects = true;

        lib_install_artifact.step.dependOn(&run_generator.step);
    }

    // const test_step = b.step("test", "Run library tests");
    // for (test_files) |file| {
    //     var tests = b.addTest(.{
    //         .root_source_file = std.build.FileSource{ .path = file },
    //         .optimize = mode,
    //     });
    //     test_step.dependOn(&tests.step);
    // }
}
