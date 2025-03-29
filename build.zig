const std = @import("std");
const Build = std.Build;

const Options = struct {
    mode: std.builtin.OptimizeMode,
    target: Build.ResolvedTarget,
    single_threaded: bool,
    target_linux: bool,
    use_vendor: bool,
};

pub fn build(b: *Build) !void {
    const options = Options{
        .mode = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{}),
        .single_threaded = b.option(bool, "single-threaded", "Build the server in single-threaded mode?") orelse false,
        .target_linux = b.option(bool, "target-linux", "Build the server for the default linux target instead of the native target") orelse false,
        .use_vendor = b.option(bool, "use-vendor", "Use vendored versions of listed dependencies (put dependencies under a vendor/ directory)") orelse false,
    };

    try buildWeb(b, options);

    const default_linux_target = try std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux" });

    const exe = b.addExecutable(.{
        .name = "zig-server",
        .root_source_file = b.path("server/main.zig"),
        .optimize = options.mode,
        .target = if (options.target_linux) b.resolveTargetQuery(default_linux_target) else options.target,
        .single_threaded = options.single_threaded,
    });

    const tortie_module = if (options.use_vendor)
        b.createModule(.{ .root_source_file = b.path("vendor/tortie/src/tortie.zig") })
    else
        b.dependency("tortie", .{}).module("tortie");
    exe.root_module.addImport("tortie", tortie_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Start the server");
    run_step.dependOn(&run_cmd.step);
}

fn buildWeb(b: *Build, options: Options) !void {
    var install_step = b.getInstallStep();

    const wasm_target = try std.Target.Query.parse(.{
        .arch_os_abi = "wasm32-freestanding",
        .cpu_features = "generic+simd128",
    });

    // Main WASM library
    const night_math = b.addExecutable(.{
        .name = "night-math",
        .root_source_file = b.path("night-math/main.zig"),
        .target = b.resolveTargetQuery(wasm_target),
        .link_libc = false,
        .optimize = options.mode,
    });
    night_math.entry = .disabled;
    night_math.rdynamic = true;

    generateStarData(b, night_math, options, &.{
        .{
            .arg = "--stars",
            .input = .{ .file = "data/sao_catalog" },
            .output = "star_data.bin",
            .import_name = "star_data",
        },
        .{
            .arg = "--constellations",
            .input = .{ .dir = "data/constellations/iau" },
            .output = "const_data.bin",
            .import_name = "const_data",
        },
        .{
            .arg = "--metadata",
            .input = .{ .dir = "data/constellations/iau" },
            .output = "const_meta.json",
        },
    });

    var node_run = try buildNode(b, options);
    // Install the artifact in dist/wasm
    const lib_install_artifact = b.addInstallArtifact(night_math, .{ .dest_dir = .{ .override = .{ .custom = "../dist/wasm" } } });

    lib_install_artifact.step.dependOn(&node_run.step);
    install_step.dependOn(&lib_install_artifact.step);
}

fn buildNode(b: *Build, options: Options) !*Build.Step.Run {
    var node_run = b.addSystemCommand(&.{"node"});
    node_run.addArg("esbuild.config.mjs");

    if (options.mode != .Debug) {
        node_run.addArg("--prod");
    }

    var dir = std.fs.cwd().openDir("node_modules", .{});

    if (dir) |*d| {
        d.close();
    } else |err| switch (err) {
        error.FileNotFound => {
            // If node_modules does not exist, add a step to install the dependencies
            var npm_install_run = b.addSystemCommand(&.{"npm"});
            npm_install_run.addArg("install");

            node_run.step.dependOn(&npm_install_run.step);
        },
        else => return err,
    }

    return node_run;
}

const StarDataConfig = struct {
    const Input = union(enum) {
        file: []const u8,
        dir: []const u8,
    };

    arg: []const u8,
    input: Input,
    output: []const u8,
    import_name: ?[]const u8 = null,
};

// Process raw star/constellation data and generate binary coordinate data.
// These will be embedded in the final library
fn generateStarData(b: *Build, main_exe: *Build.Step.Compile, options: Options, data_configs: []const StarDataConfig) void {
    const data_gen = b.addExecutable(.{
        .name = "prepare-data",
        .root_source_file = b.path("prepare-data/main.zig"),
        .optimize = .ReleaseFast,
        .target = options.target,
    });

    const run_data_gen = b.addRunArtifact(data_gen);

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
