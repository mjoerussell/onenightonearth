const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const FileSource = @This();

pub const GetFileError = error{ FileNotFound, OutOfMemory, OpenError, FileTooBig };

const relative_dir = "../web/";

/// These paths are relative to `index.html`, not the server. To get paths relative to
/// the server, prepend `relative_dir`.
///
/// The reason for this is that these are the paths that are going to be included in the 'uri' component
/// of an http request. Storing them like this allows us to modify that value as little as possible.
const allowed_paths = [_][]const u8{
    "dist/bundle.js",
    "styles/main.css",
    "assets/favicon.ico",
    "dist/wasm/night-math.wasm",
};

preloaded_files: if (builtin.mode == .Debug) void else std.StringHashMap([]const u8),

/// In debug mode, this initializer does nothing and cannot fail. All files are loaded when they are requested, in
/// order to support live updates of static files. In release mode, this will read all of the files and store them
/// in `preloaded_files`, with their base paths used as keys.
pub fn init(allocator: Allocator) !FileSource {
    if (builtin.mode == .Debug) {
        _ = allocator;
        return FileSource{
            .preloaded_files = {},
        };
    }

    const cwd = fs.cwd();
    var file_source: FileSource = undefined;
    file_source.preloaded_files = std.StringHashMap([]const u8).init(allocator);
    inline for (FileSource.allowed_paths) |path| {
        var file = cwd.openFile(FileSource.relative_dir ++ path, .{}) catch return error.OpenError;
        defer file.close();
        const file_content = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
        try file_source.preloaded_files.putNoClobber(path, file_content);
        std.log.info("Loaded file " ++ path, .{});
    }

    return file_source;
}

/// Get a file located at `file_path`. `file_path` should be relative to `index.html`, not the server.
/// In debug mode, this function always reads the file from the filesystem and sends the current content.
/// In release modes, the files are preloaded and the contents are fetched from `preloaded_files`.
pub fn getFile(file_source: FileSource, allocator: Allocator, file_path: []const u8) ![]const u8 {
    const clean_path = if (file_path[0] == '/') file_path[1..] else file_path;
    if (builtin.mode == .Debug) {
        _ = file_source;
        const cwd = fs.cwd();
        inline for (FileSource.allowed_paths) |path| {
            if (std.mem.eql(u8, path, clean_path)) {
                var file = cwd.openFile(FileSource.relative_dir ++ path, .{}) catch return error.OpenError;
                defer file.close();
                return try file.readToEndAlloc(allocator, std.math.maxInt(u32));
            }
        }

        return error.FileNotFound;
    } else {
        _ = allocator;
        return file_source.preloaded_files.get(clean_path) orelse return error.FileNotFound;
    }
}