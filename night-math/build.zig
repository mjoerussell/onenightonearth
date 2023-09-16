const std = @import("std");
const Builder = std.build.Builder;
const Target = std.build.Target;

const output_dir = "../../web/dist/wasm";
const test_files = [_][]const u8{ "src/star_math.zig", "src/math_utils.zig", "src/render.zig" };

pub fn build(b: *Builder) !void {
    const mode = b.standardOptimizeOption(.{});
    const default_target = b.standardTargetOptions(.{});

    const generate_static_data = b.option(bool, "prepare-data", "Generate artifact files from star and constellation data.") orelse false;
    const skip_ts_gen = b.option(bool, "no-ts-gen", "Skip generating a .ts file containing type definitions for exported functions and extern-compatible types.") orelse false;

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

    if (generate_static_data) {
        const data_gen = b.addExecutable(.{
            .name = "prepare-data",
            .root_source_file = std.build.FileSource{ .path = "../prepare-data/src/main.zig" },
            .optimize = .ReleaseFast,
            .target = default_target,
        });

        const run_data_gen = b.addRunArtifact(data_gen);
        run_data_gen.addArgs(&.{ "--stars", "../data/sao_catalog", "./src/star_data.bin" });
        run_data_gen.addArgs(&.{ "--constellations", "../data/constellations/iau", "./src/const_data.bin" });
        run_data_gen.step.dependOn(&data_gen.step);
        run_data_gen.has_side_effects = true;

        lib_install_artifact.step.dependOn(&run_data_gen.step);
    }

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
}
