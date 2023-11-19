const std = @import("std");
const Builder = std.build.Builder;
const Target = std.build.Target;

const output_dir = "../../web/dist/wasm";
const test_files = [_][]const u8{ "src/star_math.zig", "src/math_utils.zig", "src/render.zig" };

pub fn build(b: *Builder) !void {
    const mode = b.standardOptimizeOption(.{});
    const default_target = b.standardTargetOptions(.{});

    // Process raw star/constellation data and generate binary coordinate data.
    // These will be embedded in the final library
    const data_gen = b.addExecutable(.{
        .name = "prepare-data",
        .root_source_file = std.build.FileSource{ .path = "../prepare-data/src/main.zig" },
        .optimize = .ReleaseFast,
        .target = default_target,
    });

    const run_data_gen = b.addRunArtifact(data_gen);

    run_data_gen.addArg("--stars");
    run_data_gen.addFileArg(.{ .path = "../data/sao_catalog" });
    const star_output = run_data_gen.addOutputFileArg("star_data.bin");

    run_data_gen.addArg("--constellations");
    run_data_gen.addDirectoryArg(.{ .path = "../data/constellations/iau" });
    const const_output = run_data_gen.addOutputFileArg("const_data.bin");

    // Main library
    const lib = b.addStaticLibrary(.{
        .name = "night-math",
        .root_source_file = std.build.FileSource{ .path = "src/main.zig" },
        .target = try std.zig.CrossTarget.parse(.{
            .arch_os_abi = "wasm32-freestanding",
            .cpu_features = "generic+simd128",
        }),
        .optimize = mode,
    });

    lib.addAnonymousModule("star_data", .{ .source_file = star_output });
    lib.addAnonymousModule("const_data", .{ .source_file = const_output });

    const lib_install_artifact = b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = output_dir } } });
    b.getInstallStep().dependOn(&lib_install_artifact.step);

    // This executable will generate a Typescript file with types that can be applied to the imported WASM module.
    // This makes it easier to make adjustments to the lib, because changes in the interface will be reflected as type errors.
    const ts_gen = b.addExecutable(.{
        .name = "gen",
        .root_source_file = std.build.FileSource{ .path = "generate_interface.zig" },
        .optimize = .ReleaseSafe,
        .target = default_target,
    });

    ts_gen.addAnonymousModule("star_data", .{ .source_file = star_output });
    ts_gen.addAnonymousModule("const_data", .{ .source_file = const_output });

    const run_generator = b.addRunArtifact(ts_gen);
    run_generator.step.dependOn(&ts_gen.step);
    run_generator.has_side_effects = true;

    lib_install_artifact.step.dependOn(&run_generator.step);
}
