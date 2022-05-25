const std = @import("std");
const fs = std.fs;
const deflate = std.compress.deflate;
const Allocator = std.mem.Allocator;

const CompressedFileWriter = @This();
const CompressingWriter = deflate.Compressor(fs.File.Writer);

file: fs.File,
compressing_writer: CompressingWriter,

pub fn init(allocator: Allocator, filename: []const u8) !CompressedFileWriter {
    const cwd = fs.cwd();

    var out_file = try cwd.createFile(filename, .{});

    return CompressedFileWriter{
        .file = out_file,
        .compressing_writer = try deflate.compressor(allocator, out_file.writer(), .{ .level = .best_compression }),
    };
}

pub fn deinit(cfw: *CompressedFileWriter) void {
    cfw.compressing_writer.flush() catch {};
    cfw.compressing_writer.deinit();
    cfw.file.close();
}

pub fn writer(cfw: *CompressedFileWriter) CompressingWriter.Writer {
    return cfw.compressing_writer.writer();
}