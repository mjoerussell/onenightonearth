const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.file_source);

extern fn CreateFileMappingA(
    hFile: std.os.windows.HANDLE, 
    lpFileMappingAttributes: ?[*]std.os.windows.SECURITY_ATTRIBUTES,
    flProtect: u32,
    dwMaximumSizeHigh: u32,
    dwMaximumSizeLow: u32,
    lpName: ?[*]const u8
) callconv(.C) std.os.windows.HANDLE;

extern fn MapViewOfFile(
    hFileMappingObject: std.os.windows.HANDLE,
    dwDesiredAccess: u32,
    dwFileOffsetHigh: u32,
    dwFileOffsetLow: u32,
    dwNumberOfBytesToMap: usize,
) callconv(.C) *anyopaque;

extern fn UnmapViewOfFile(lpBaseAddress: *anyopaque) callconv(.C) c_int;

const FileSource = @This();

pub const GetFileError = error{ FileNotFound, OutOfMemory, OpenError, FileTooBig };

const relative_dir = "../web/";
const compressed_file_prefix = "compressed/";
/// These paths are relative to `index.html`, not the server. To get paths relative to
/// the server, prepend `relative_dir`.
///
/// The reason for this is that these are the paths that are going to be included in the 'uri' component
/// of an http request. Storing them like this allows us to modify that value as little as possible.
const allowed_paths_relative = [_][]const u8{
    "index.html",
    "dist/bundle.js",
    "styles/main.css",
    "assets/favicon.ico",
    "dist/wasm/night-math.wasm",
};

const allowed_paths_absolute = [_][]const u8{
    "star_data.bin",
    "const_data.bin",
    "const_meta.json",
};

mapped_files: std.StringHashMap([]const u8),
allocator: Allocator,
is_compressed: bool = builtin.mode != .Debug,

pub fn init(allocator: Allocator) !FileSource {
    var file_source = FileSource{ 
        .mapped_files = std.StringHashMap([]const u8).init(allocator), 
        .allocator = allocator,
    };
    errdefer file_source.deinit();

    if (builtin.mode != .Debug) {
        const cwd = fs.cwd();
        cwd.makeDir(compressed_file_prefix) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        try file_source.initFileMappings();
    }

    return file_source;
}

/// Unmap all files and deinitialize the `mapped_files` hash map.
pub fn deinit(file_source: *FileSource) void {
    var iter = file_source.mapped_files.valueIterator();
    while (iter.next()) |mapping| {
        deinitFileMapping(mapping.*);
    }
    file_source.mapped_files.deinit();
}

/// Unmap a file from memory.
fn deinitFileMapping(mapping: []const u8) void {
    switch (builtin.os.tag) {
        .windows => _ = UnmapViewOfFile(@intToPtr(*anyopaque, @ptrToInt(mapping.ptr))),
        else => std.os.munmap(@alignCast(std.mem.page_size, mapping)),
    }
}

pub fn getFile(file_source: FileSource, path: []const u8) ![]const u8 {
    const clean_path = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;
    if (builtin.mode == .Debug) {
        const absolute_path = try getAbsolutePath(clean_path);
        var file = try fs.cwd().openFile(absolute_path, .{});
        defer file.close();

        return try file.readToEndAlloc(file_source.allocator, std.math.maxInt(u32));
    }
    return file_source.mapped_files.get(clean_path) orelse error.FileNotFound;
}

fn getAbsolutePath(path: []const u8) error{FileNotFound}![]const u8 {
    inline for (FileSource.allowed_paths_relative) |allowed_path| {
        if (std.mem.eql(u8, allowed_path, path)) {
            return FileSource.relative_dir ++ allowed_path;
        }
    }

    inline for (FileSource.allowed_paths_absolute) |allowed_path| {
        if (std.mem.eql(u8, allowed_path, path)) {
            return allowed_path;
        }
    }

    return error.FileNotFound;
}

/// Initialize all of the file mappings for the files defined in `allowed_paths_relative` and `allowed_paths_absolue`.
/// The difference between these two sets of paths is that paths in `allowed_paths_relative` will be prepended with
/// `FileSource.relative_dir` before being opened, while `allowed_paths_absolute` are not modified.
///
/// For both sets of files, the mapped data will be inserted into the `mapped_files` hash map with the unmodified
/// paths set as the keys.
fn initFileMappings(file_source: *FileSource) !void {
    inline for (allowed_paths_relative) |file_path| {
        var mapping = try createFileMapping(file_source.allocator, FileSource.relative_dir ++ file_path);
        errdefer deinitFileMapping(mapping);

        try file_source.mapped_files.putNoClobber(file_path, mapping);
    }

    inline for (allowed_paths_absolute) |file_path| {
        var mapping = try createFileMapping(file_source.allocator, file_path);
        errdefer deinitFileMapping(mapping);

        try file_source.mapped_files.putNoClobber(file_path, mapping);
    }
}

fn createFileMapping(allocator: Allocator, file_path: []const u8) ![]const u8 {
    const clean_path = blk: {
        if (std.mem.startsWith(u8, file_path, FileSource.relative_dir)) {
            break :blk file_path[FileSource.relative_dir.len..];
        } else {
            break :blk file_path;
        }
    };
    
    var dest_path_buf: [FileSource.compressed_file_prefix.len + 100]u8 = undefined;


    var dest_path = try std.fmt.bufPrint(&dest_path_buf, FileSource.compressed_file_prefix ++ "{s}", .{clean_path});
    log.debug("Writing compressed file to path {s}", .{dest_path});
    
    var target_file = try copyAndCompress(allocator, file_path, dest_path);
    defer target_file.close();

    const file_size = blk: {
        const stat = target_file.stat() catch break :blk 0;
        break :blk stat.size;
    };

    return switch (builtin.os.tag) {
        .windows => blk: {
            var map_handle = CreateFileMappingA(target_file.handle, null, std.os.windows.PAGE_READONLY, 0, 0, null);
            defer std.os.windows.CloseHandle(map_handle);

            break :blk @ptrCast([*]u8, MapViewOfFile(map_handle, 0x0004, 0, 0, 0))[0..file_size];
        },
        else => try std.os.mmap(null, file_size, std.os.PROT.READ, std.os.linux.MAP.PRIVATE, target_file.handle, 0),
    };
}

fn copyAndCompress(allocator: Allocator, source: []const u8, destination: []const u8) !fs.File {
    const cwd = fs.cwd();

    var source_file = cwd.openFile(source, .{}) catch |err| {
        log.err("Error opening file {s}: {}", .{source, err});
        return err;
    };
    defer source_file.close();
    
    var dest_file = try createFileAtPath(destination);
    errdefer dest_file.close();

    var compressor = try std.compress.deflate.compressor(allocator, dest_file.writer(), .{ .level = .best_compression });
    defer compressor.deinit();

    var read_buffer: [std.mem.page_size]u8 = undefined;

    var bytes_read = try source_file.readAll(&read_buffer);
    while (bytes_read > 0) {
        _ = try compressor.write(read_buffer[0..bytes_read]);
        if (bytes_read < read_buffer.len) break;
        bytes_read = try source_file.readAll(&read_buffer);
    }

    try compressor.flush();
    return dest_file;
}

fn createFileAtPath(path_with_filename: []const u8) !fs.File {
    var parts = std.mem.split(u8, path_with_filename, "/");

    var current_dir = fs.cwd();
    var current_part = parts.next() orelse return error.InvalidPath;
    while (parts.next()) |next_part| : (current_part = next_part) {
        current_dir = current_dir.makeOpenPath(current_part, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => try current_dir.openDir(current_part, .{}),
            else => {
                log.err("Error trying to create/open subfolder {s}: {}", .{path_with_filename, err});
                return err;
            }
        };
    }

    return current_dir.createFile(current_part, .{ .read = true }) catch |err| {
        log.err("Error creating file {s}: {}", .{current_part, err});
        return err;
    };
}

