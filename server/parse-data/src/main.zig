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

    fn parse(data: []const u8) Star {
        var star: Star = undefined;

        var parts_iter = std.mem.split(u8, data, "|");
        var part_index: u8 = 0;
        while (parts_iter.next()) |part| : (part_index += 1) {
            if (part_index > 14) break;
            switch (part_index) {
                1 => star.right_ascension = std.fmt.parseFloat(f32, part) catch 0,
                5 => star.declination = std.fmt.parseFloat(f32, part) catch 0,
                13 => {
                    const dimmest_visible: f32 = 18.6;
                    const brightest_value: f32 = -4.6;
                    const v_mag = std.fmt.parseFloat(f32, part) catch dimmest_visible;
                    const mag_display_factor = (dimmest_visible - (v_mag - brightest_value)) / dimmest_visible;
                    star.brightness = mag_display_factor;
                },
                14 => {
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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    const stars = try readSaoCatalog(allocator, "sao_catalog");
    defer allocator.free(stars);

    for (stars) |star, index| {
        if (index % 10_000 == 0) {
            std.debug.print("{}\n", .{star});
        } 
    }

}

fn readSaoCatalog(allocator: *Allocator, filename: []const u8) ![]Star {
    const cwd = fs.cwd();
    const sao_catalog = try cwd.openFile(filename, .{});

    var catalog_reader = sao_catalog.reader();

    var star_list = std.ArrayList(Star).init(allocator);
    errdefer star_list.deinit();

    var read_buffer: [500]u8 = undefined;
    var read_start_index: usize = 0;
    var line_start_index: usize = 0;
    var line_end_index: usize = 0;
    read_loop: while (catalog_reader.readAll(read_buffer[read_start_index..])) |bytes_read| {
        std.debug.print("Read {} bytes", .{bytes_read});
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
                std.debug.print("Got star at {}-{}\n", .{line_start_index, line_end_index});
                const star = Star.parse(line);
                try star_list.append(star);
            }

            line_start_index = line_end_index + 1; 
            line_end_index = line_start_index;
        }
    } else |err| return err;

    return star_list.toOwnedSlice();
}
