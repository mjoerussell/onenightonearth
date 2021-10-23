const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const SpectralType = enum(u8) {
    O,
    B,
    A,
    F,
    G,
    K,
    M,
};

pub const Star = packed struct {
    right_ascension: f32,
    declination: f32,
    brightness: f32,
    spec_type: SpectralType,

    fn parse(data: []const u8) !Star {
        var star: Star = undefined;

        var parts_iter = std.mem.split(u8, data, "|");
        var part_index: u8 = 0;
        while (parts_iter.next()) |part| : (part_index += 1) {
            if (part_index > 14) break;
            switch (part_index) {
                1 => star.right_ascension = try std.fmt.parseFloat(f32, part),
                5 => star.declination = try std.fmt.parseFloat(f32, part),
                13 => {
                    const dimmest_visible: f32 = 18.6;
                    const brightest_value: f32 = -4.6;
                    const v_mag = std.fmt.parseFloat(f32, part) catch dimmest_visible;
                    const mag_display_factor = (dimmest_visible - (v_mag - brightest_value)) / dimmest_visible;
                    star.brightness = mag_display_factor;
                },
                14 => {
                    if (part.len < 1) {
                        star.spec_type = .A;
                        continue;
                    }
                    star.spec_type = switch (std.ascii.toLower(part[0])) {
                        'o' => SpectralType.O,
                        'b' => SpectralType.B,
                        'a' => SpectralType.A,
                        'f' => SpectralType.F,
                        'g' => SpectralType.G,
                        'k' => SpectralType.K,
                        'm' => SpectralType.M,
                        else => SpectralType.A,
                    };
                },
                else => {},
            }
        }

        return star;
    }
};

pub fn main() anyerror!void {
    var timer = std.time.Timer.start() catch unreachable;

    const start = timer.read();
    const output_file = try readSaoCatalog("sao_catalog", "star_data.bin");
    defer output_file.close();

    const end = timer.read();

    std.debug.print("Parsing took {d:.4} ms\n", .{(end - start) / 1_000_000});
}

fn readSaoCatalog(catalog_filename: []const u8, out_filename: []const u8) !fs.File {
    const cwd = fs.cwd();
    const sao_catalog = try cwd.openFile(catalog_filename, .{});
    defer sao_catalog.close();

    const output_file = try cwd.createFile(out_filename, .{});
    errdefer {
        output_file.close();
        cwd.deleteFile(out_filename) catch {};
    }

    var output_buffered_writer = std.io.bufferedWriter(output_file.writer());
    var output_writer = output_buffered_writer.writer();

    var read_buffer: [std.mem.page_size]u8 = undefined;
    var read_start_index: usize = 0;
    var line_start_index: usize = 0;
    var line_end_index: usize = 0;

    var star_count: u64 = 0;

    read_loop: while (sao_catalog.readAll(read_buffer[read_start_index..])) |bytes_read| {
        if (bytes_read == 0) break;
        // Get all the lines currently read into the buffer
        while (line_start_index < read_buffer.len and line_end_index < read_buffer.len) {
            // Search for the end of the current line
            line_end_index = while (line_end_index < read_buffer.len) : (line_end_index += 1) {
                if (read_buffer[line_end_index] == '\n') break line_end_index;
            } else {
                // If it gets to the end of the buffer without reaching the end of the line, move the current in-progress
                // line to the beginning of the buffer, reset the indices to their new positions, and read more data into
                // the buffer
                std.mem.copy(u8, read_buffer[0..], read_buffer[line_start_index..]);
                line_end_index -= line_start_index;
                read_start_index = line_end_index;
                line_start_index = 0;
                continue :read_loop;
            };

            const line = read_buffer[line_start_index..line_end_index];
            if (std.mem.startsWith(u8, line, "SAO")) {
                if (Star.parse(line)) |star| {
                    if (star.brightness >= 0.3) {
                        star_count += 1;
                        try output_writer.writeAll(std.mem.toBytes(star)[0..]);
                    }
                } else |_| {}
            }

            line_start_index = line_end_index + 1; 
            line_end_index = line_start_index;
        }

        line_start_index = 0;
        line_end_index = 0;
        read_start_index = 0;
    } else |err| return err;

    try output_buffered_writer.flush();

    std.debug.print("Wrote {} stars\n", .{star_count});
    return output_file;
}
