const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.file_source);

const FileSource = @This();

pub const GetFileError = error{ FileNotFound, OutOfMemory, OpenError, FileTooBig };

pub const FilePath = union(enum) {
    /// Define the necessary hashing functions used to use values of this struct
    /// as keys in a hash map.
    const HashContext = struct {
        pub fn hash(ctx: @This(), key: FilePath) u64 {
            const Wyhash = std.hash.Wyhash;
            _ = ctx;
            return switch (key) {
                .absolute => |path| Wyhash.hash(0, path),
                .relative => |path| blk: {
                    const dir_hash = Wyhash.hash(0, path.dir_path);
                    break :blk Wyhash.hash(dir_hash, path.relative_path);
                },
            };
        }

        pub fn eql(ctx: @This(), a: FilePath, b: FilePath) bool {
            _ = ctx;
            return switch (a) {
                .absolute => |a_path| switch (b) {
                    .absolute => |b_path| std.mem.eql(u8, a_path, b_path),
                    .relative => false,
                },
                .relative => |a_path| switch (b) {
                    .absolute => false,
                    .relative => |b_path| blk: {
                        const dir_eql = std.mem.eql(u8, a_path.dir_path, b_path.dir_path);
                        const file_path_eql = std.mem.eql(u8, a_path.relative_path, b_path.relative_path);
                        break :blk dir_eql and file_path_eql;
                    },
                },
            };
        }
    };

    absolute: []const u8,
    relative: struct {
        dir_path: []const u8,
        relative_path: []const u8,
    },

    /// Create a new absolute file path. The input path will be used, unmodified, when trying to open the file at
    /// the specified location.
    pub fn absolute(path: []const u8) FilePath {
        return FilePath{ .absolute = path };
    }

    /// Create a new relative file path. The first parameter is the relative prefix, which can be *ignored* for the purpose
    /// of looking up the file.
    ///
    /// The intended use of the relative path is to allow the client to ask for static files by some kind of relative path
    /// (for instance, relative to `index.html`) without having to know what the static directory is. File lookup will be
    /// performed using the two paths concatenated together with a file separator in-between.
    pub fn relative(dir_path: []const u8, relative_file_path: []const u8) FilePath {
        return FilePath{
            .relative = .{ 
                .dir_path = dir_path,
                .relative_path = relative_file_path,
            },
        };
    }

    /// Get the full file path represented by this `FilePath` object. `absolute` paths will return
    /// the inner value unmodified, will not allocate, and cannot fail. `relative` paths will concatenate
    /// the `dir_path` and `relative_path` values with a path separator in-between. This concatenation does
    /// allocate, and therefore can fail.
    pub fn getFullPath(file_path: FilePath, allocator: Allocator) ![]const u8 {
        switch (file_path) {
            .absolute => |fp| return fp,
            .relative => |fp| {
                var path_buf = try allocator.alloc(u8, fp.dir_path.len + fp.relative_path.len + 1);
                std.mem.copy(u8, path_buf, fp.dir_path);
                path_buf[fp.dir_path.len] = '/';
                std.mem.copy(u8, path_buf[fp.dir_path.len + 1..], fp.relative_path);
                return path_buf;
            },
        }
    }

    /// Try to open the file at the path represented by this `FilePath` object.
    pub fn open(file_path: FilePath, allocator: Allocator) !fs.File {
        const full_path = try file_path.getFullPath(allocator);
        const cwd = fs.cwd();
        return try cwd.openFile(full_path, .{});
    }

    /// Test to see if the given path matches this `FilePath`. For `absolute` file paths, the input
    /// value and the stored path value will be compared directly. For `relative` file paths, the
    /// input value will only be compared against the `relative_path` value.
    pub fn matches(file_path: FilePath, test_path: []const u8) bool {
        return switch (file_path) {
            .absolute => |fp| std.mem.eql(u8, fp, test_path),
            .relative => |fp| std.mem.eql(u8, fp.relative_path, test_path),
        };
    }
};

const FilePathHashMap = std.HashMap(FilePath, []const u8, FilePath.HashContext, std.hash_map.default_max_load_percentage);

pub const FileSourceConfig = struct {
    should_compress: bool = builtin.mode != .Debug,
    hot_reload: bool = builtin.mode == .Debug,
};

allocator: Allocator,
allowed_paths: []const FilePath,
mapped_files: FilePathHashMap,
config: FileSourceConfig,

pub fn init(allocator: Allocator, allowed_paths: []const FilePath, config: FileSourceConfig) !FileSource {
    var file_source = FileSource{
        .allocator = allocator,
        .allowed_paths = allowed_paths,
        .mapped_files = FilePathHashMap.init(allocator),
        .config = config,
    };
    errdefer file_source.deinit();

    // If the file source is configured to hot reload its files, then there's no point in
    // loading everything into memory - the files are going to be re-read every time they're accessed.
    // In that case, we're done initializing
    if (file_source.config.hot_reload) return file_source;

    for (allowed_paths) |path| {
        var file = try path.open(allocator);
        defer file.close();

        var contents = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
        if (file_source.config.should_compress) {
            defer allocator.free(contents);

            var compressed = try copyAndCompress(allocator, contents);
            try file_source.mapped_files.put(path, compressed);
        } else {
            try file_source.mapped_files.put(path, contents);
        }
    }

    return file_source;
}

pub fn deinit(file_source: *FileSource) void {
    var file_iter = file_source.mapped_files.valueIterator();
    while (file_iter.next()) |value| {
        file_source.allocator.free(value.*);
    }

    file_source.allocator.free(file_source.allowed_paths);
    file_source.mapped_files.deinit();
}

pub fn getFile(file_source: FileSource, path: []const u8) ![]const u8 {
    const clean_path = if (path[0] == '/') path[1..] else path;

    if (file_source.getAllowedFilePath(clean_path)) |allowed_path| {
        if (file_source.config.hot_reload) {
            var file = try allowed_path.open(file_source.allocator);
            defer file.close();

            const content = try file.readToEndAlloc(file_source.allocator, std.math.maxInt(u32));
            if (file_source.config.should_compress) {
                defer file_source.allocator.free(content);
                return try copyAndCompress(file_source.allocator, content);
            } 
            
            return content;
        } 
        
        return file_source.mapped_files.get(allowed_path) orelse error.FileNotFound;
    }

    log.debug("File {s} was not in the list of allowed paths", .{path});
    return error.FileNotFound;
}

/// Iterate over the allowed file paths and return the first one that matches
/// the input path. If none are a match, then return `null`.
fn getAllowedFilePath(file_source: FileSource, path: []const u8) ?FilePath {
    for (file_source.allowed_paths) |allowed_path| {
        if (allowed_path.matches(path)) {
            return allowed_path;
        }
    }

    return null;
}

pub fn deinitFile(file_source: FileSource, content: []const u8) void {
    if (!file_source.config.hot_reload) return;
    file_source.allocator.free(content);
}

fn copyAndCompress(allocator: Allocator, source: []const u8) ![]const u8 {
    var dest_buffer = std.ArrayList(u8).init(allocator);
    errdefer dest_buffer.deinit();
    
    var compressor = try std.compress.deflate.compressor(allocator, dest_buffer.writer(), .{ .level = .best_compression });
    defer compressor.deinit();

    _ = try compressor.write(source);

    try compressor.flush();

    return dest_buffer.toOwnedSlice();
}
