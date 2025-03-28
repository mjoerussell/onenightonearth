const std = @import("std");
const Build = std.Build;
const Target = Build.Target;

const output_dir = "../../web/dist/wasm";
const test_files = [_][]const u8{ "src/star_math.zig", "src/math_utils.zig", "src/render.zig" };

pub fn build(b: *Build) !void {
    const mode = b.standardOptimizeOption(.{});
    const default_target = b.standardTargetOptions(.{});

    const wasm_target = try std.Target.Query.parse(.{
        .arch_os_abi = "wasm32-freestanding",
        .cpu_features = "generic+simd128",
    });

    // Main library
    // Must build as an EXE since https://github.com/ziglang/zig/pull/17815
    const exe = b.addExecutable(.{
        .name = "night-math",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(wasm_target),
        .link_libc = false,
        .optimize = mode,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    // Process raw star/constellation data and generate binary coordinate data.
    // These will be embedded in the final library
    const data_gen = b.addExecutable(.{
        .name = "prepare-data",
        .root_source_file = b.path("../prepare-data/src/main.zig"),
        .optimize = .ReleaseFast,
        .target = default_target,
    });

    generateStarData(b, exe, data_gen, &.{
        .{
            .arg = "--stars",
            .input = .{ .file = "../data/sao_catalog" },
            .output = "star_data.bin",
            .import_name = "star_data",
        },
        .{
            .arg = "--constellations",
            .input = .{ .dir = "../data/constellations/iau" },
            .output = "const_data.bin",
            .import_name = "const_data",
        },
        .{
            .arg = "--metadata",
            .input = .{ .dir = "../data/constellations/iau" },
            .output = "const_meta.json",
        },
    });

    // Install the artifact in a custom directory - will be emitted in web/dist/wasm
    const lib_install_artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = output_dir } } });
    b.getInstallStep().dependOn(&lib_install_artifact.step);

    // This executable will generate a Typescript file with types that can be applied to the imported WASM module.
    // This makes it easier to make adjustments to the lib, because changes in the interface will be reflected as type errors.
    const ts_gen = b.addExecutable(.{
        .name = "gen",
        .root_source_file = b.path("generate_interface.zig"),
        .optimize = .ReleaseSafe,
        .target = default_target,
    });

    const run_generator = b.addRunArtifact(ts_gen);
    run_generator.step.dependOn(&ts_gen.step);
    run_generator.has_side_effects = true;
}

const DataConfig = struct {
    const Input = union(enum) {
        file: []const u8,
        dir: []const u8,
    };

    arg: []const u8,
    input: Input,
    output: []const u8,
    import_name: ?[]const u8 = null,
};

fn generateStarData(b: *Build, main_exe: *Build.Step.Compile, generator_exe: *Build.Step.Compile, data_configs: []const DataConfig) void {
    const run_data_gen = b.addRunArtifact(generator_exe);

    for (data_configs) |config| {
        run_data_gen.addArg(config.arg);
        switch (config.input) {
            .file => |path| run_data_gen.addFileArg(b.path(path)),
            .dir => |path| run_data_gen.addDirectoryArg(b.path(path)),
        }

        const output = run_data_gen.addOutputFileArg(config.output);
        if (config.import_name) |import_name| {
            main_exe.root_module.addAnonymousImport(import_name, .{ .root_source_file = output });
        } else {
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .prefix, config.output).step);
        }
    }
}
