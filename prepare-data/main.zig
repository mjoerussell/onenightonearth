const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const nightsky = @import("nightsky");
const FixedPoint = nightsky.DefaultFixedPoint;
const ExternStar = nightsky.Star.ExternStar;
const ExternConstellation = nightsky.Constellation.ExternConstellation;
const SpectralType = nightsky.Star.SpectralType;
const ExternSkyCoord = nightsky.SkyCoord.ExternSkyCoord;

const log = std.log.scoped(.prepare_data);

/// A standard degree-to-radian conversion function.
pub fn degToRad(degrees: anytype) @TypeOf(degrees) {
    return degrees * (std.math.pi / 180.0);
}

/// Convert longitude values from degrees to radians. This differs from a normal degree-to-radian conversion
/// because longitude values are written in the range [-180, 180], but the resulting radian values should be
/// between [0, 2pi].
pub fn degToRadLong(degrees: anytype) @TypeOf(degrees) {
    const norm_deg = if (degrees < 0) degrees + 360 else degrees;
    return degToRad(norm_deg);
}

pub fn spectralTypeFromChar(char: u8) ?SpectralType {
    return switch (char) {
        'o', 'O' => .O,
        'b', 'B' => .B,
        'a', 'A' => .A,
        'f', 'F' => .F,
        'g', 'G' => .G,
        'k', 'K' => .K,
        'm', 'M' => .M,
        else => null,
    };
}

const SkyFile = struct {
    name: []const u8,
    epithet: []const u8,
    constellation: ExternConstellation,

    pub fn parse(allocator: Allocator, data: []const u8) !SkyFile {
        const ParseState = enum {
            stars,
            asterism,
            boundaries,
        };

        var sky_file: SkyFile = undefined;

        sky_file.constellation.is_zodiac = false;

        var stars = std.StringHashMap(ExternSkyCoord).init(allocator);
        defer stars.deinit();

        var boundary_list: std.ArrayList(ExternSkyCoord) = .empty;
        errdefer boundary_list.deinit(allocator);

        var asterism_list: std.ArrayList(ExternSkyCoord) = .empty;
        errdefer asterism_list.deinit(allocator);

        var line_iter = std.mem.splitSequence(u8, data, "\r\n");

        var parse_state: ParseState = .stars;

        while (line_iter.next()) |line| {
            if (std.mem.trim(u8, line, " ").len == 0) continue;

            if (std.mem.indexOf(u8, line, "#zodiac")) |_| {
                sky_file.constellation.is_zodiac = true;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@name")) |_| {
                var line_split = std.mem.splitScalar(u8, line, '=');
                _ = line_split.next();
                const name = line_split.next().?;
                const trimmed_name = std.mem.trim(u8, name, " ");
                const name_copy = try allocator.alloc(u8, trimmed_name.len);
                @memcpy(name_copy, trimmed_name);
                sky_file.name = name_copy;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@epithet")) |_| {
                var line_split = std.mem.splitScalar(u8, line, '=');
                _ = line_split.next();
                const epithet = line_split.next().?;
                const trimmed_epithet = std.mem.trim(u8, epithet, " ");
                const epithet_copy = try allocator.alloc(u8, trimmed_epithet.len);
                @memcpy(epithet_copy, trimmed_epithet);
                sky_file.epithet = epithet_copy;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@stars")) |_| {
                parse_state = .stars;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@asterism")) |_| {
                parse_state = .asterism;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@boundaries")) |_| {
                parse_state = .boundaries;
                continue;
            }

            if (!std.mem.startsWith(u8, line, "@")) {
                switch (parse_state) {
                    .stars => {
                        var parts = std.mem.splitScalar(u8, line, ',');
                        const star_name = std.mem.trim(u8, parts.next().?, " ");
                        const right_ascension = std.mem.trim(u8, parts.next().?, " ");
                        const declination = std.mem.trim(u8, parts.next().?, " ");

                        const ra_value = try std.fmt.parseFloat(f32, right_ascension);
                        const dec_value = try std.fmt.parseFloat(f32, declination);

                        const star_coord = ExternSkyCoord{
                            .right_ascension = FixedPoint.fromFloat(degToRadLong(ra_value)),
                            .declination = FixedPoint.fromFloat(degToRad(dec_value)),
                        };

                        try stars.put(star_name, star_coord);
                    },
                    .asterism => {
                        var parts = std.mem.splitScalar(u8, line, ',');
                        const star_a_name = std.mem.trim(u8, parts.next().?, " ");
                        const star_b_name = std.mem.trim(u8, parts.next().?, " ");

                        if (stars.get(star_a_name)) |star_a| {
                            if (stars.get(star_b_name)) |star_b| {
                                try asterism_list.append(allocator, star_a);
                                try asterism_list.append(allocator, star_b);
                            }
                        }
                    },
                    .boundaries => {
                        var parts = std.mem.splitScalar(u8, line, ',');
                        const right_ascension_long = std.mem.trim(u8, parts.next().?, " ");
                        const declination = std.mem.trim(u8, parts.next().?, " ");

                        var right_ascension_parts = std.mem.splitScalar(u8, right_ascension_long, ' ');
                        const ra_hours = try std.fmt.parseInt(u32, right_ascension_parts.next().?, 10);
                        const ra_minutes = try std.fmt.parseInt(u32, right_ascension_parts.next().?, 10);
                        const ra_seconds = try std.fmt.parseFloat(f32, right_ascension_parts.next().?);

                        const right_ascension = @as(f32, @floatFromInt(ra_hours * 15)) + ((@as(f32, @floatFromInt(ra_minutes)) / 60) * 15) + ((ra_seconds / 3600) * 15);
                        const dec_value = try std.fmt.parseFloat(f32, std.mem.trim(u8, declination, " "));
                        const boundary_coord = ExternSkyCoord{
                            .right_ascension = FixedPoint.fromFloat(degToRadLong(right_ascension)),
                            .declination = FixedPoint.fromFloat(degToRad(dec_value)),
                        };

                        try boundary_list.append(allocator, boundary_coord);
                    },
                }
            }
        }

        sky_file.constellation.boundaries = try boundary_list.toOwnedSlice(allocator);
        sky_file.constellation.asterism = try asterism_list.toOwnedSlice(allocator);

        return sky_file;
    }

    fn deinit(sky_file: SkyFile, allocator: Allocator) void {
        allocator.free(sky_file.name);
        allocator.free(sky_file.epithet);
        sky_file.constellation.deinit(allocator);
    }
};

fn parseStar(data: []const u8) !ExternStar {
    var star: ExternStar = undefined;

    var parts_iter = std.mem.splitScalar(u8, data, '|');
    var part_index: u8 = 0;

    var right_ascension: f32 = 0;
    var declination: f32 = 0;
    while (parts_iter.next()) |part| : (part_index += 1) {
        if (part_index > 14) break;
        switch (part_index) {
            1 => right_ascension = try std.fmt.parseFloat(f32, part),
            5 => declination = try std.fmt.parseFloat(f32, part),
            13 => {
                const dimmest_visible: f32 = 18.6;
                const brightest_value: f32 = -4.6;
                const v_mag = std.fmt.parseFloat(f32, part) catch dimmest_visible;
                const mag_display_factor = (dimmest_visible - (v_mag - brightest_value)) / dimmest_visible;

                star.brightness = blk: {
                    const b = mag_display_factor + 0.15;
                    if (b >= 1.0) {
                        break :blk 255;
                    } else if (b <= 0.45) {
                        break :blk 0;
                    } else {
                        break :blk @as(u8, @intFromFloat(b * 255.0));
                    }
                };
            },
            14 => {
                if (part.len < 1) {
                    star.spec_type = .A;
                    continue;
                }
                star.spec_type = spectralTypeFromChar(part[0]) orelse .A;
            },
            else => {},
        }
    }

    star.right_ascension = FixedPoint.fromFloat(degToRadLong(right_ascension));
    star.declination = FixedPoint.fromFloat(degToRad(declination));

    return star;
}

const Arguments = struct {
    const SourceDest = struct {
        source: []const u8,
        dest: []const u8,
    };

    /// Controls the generation of star coordinates. Expects a path to the sao_catalog file as the source.
    stars: SourceDest,
    constellations: SourceDest,
    metadata: SourceDest,

    pub fn init(args: []const []const u8) !Arguments {
        var arguments: Arguments = undefined;

        // var arg_index: usize = 0;
        // while (arg_index < args.len) : (arg_index += 1) {
        inline for (@typeInfo(@This()).@"struct".fields) |field| {
            const arg_name = "--" ++ field.name;
            var found_arg = false;
            for (0..args.len) |arg_index| {
                if (std.mem.eql(u8, args[arg_index], arg_name)) {
                    if (args.len < arg_index + 2) {
                        log.err("Wrong number of arguments provided for " ++ arg_name, .{});
                        return error.MissingArguments;
                    }

                    @field(arguments, field.name) = SourceDest{
                        .source = args[arg_index + 1],
                        .dest = args[arg_index + 2],
                    };

                    found_arg = true;
                }
            }

            if (!found_arg) {
                return error.MissingArgument;
            }
        }

        return arguments;
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const arguments = try Arguments.init(args);

    var io_threaded: Io.Threaded = .init(allocator);
    const io = io_threaded.io();

    var stars_future = io.async(readSaoCatalog, .{ allocator, io, arguments.stars.source });
    defer _ = stars_future.cancel(io) catch {};

    var const_future = io.async(readSkyFiles, .{ allocator, io, arguments.constellations.source });
    defer _ = const_future.cancel(io) catch {};

    const stars: []ExternStar = try stars_future.await(io);
    try writeStarData(stars, arguments.stars.dest);

    const sky_files: []SkyFile = try const_future.await(io);
    defer {
        for (sky_files) |sky_file| sky_file.deinit(allocator);
    }
    try writeConstellationData(sky_files, arguments.constellations.dest);
    try writeConstellationMetadata(sky_files, arguments.metadata.dest);
}

fn readSaoCatalog(allocator: Allocator, io: Io, catalog_filename: []const u8) ![]ExternStar {
    // const cwd = fs.cwd();
    // const sao_catalog = try cwd.openFile(catalog_filename, .{});
    const sao_catalog = try std.Io.Dir.cwd().openFile(io, catalog_filename, .{});
    defer sao_catalog.close(io);

    var star_list: std.ArrayList(ExternStar) = .empty;
    errdefer star_list.deinit(allocator);

    var read_buffer: [4096]u8 = undefined;
    var reader = sao_catalog.reader(io, &.{});

    var read_start_index: usize = 0;
    var line_start_index: usize = 0;
    var line_end_index: usize = 0;

    read_loop: while (reader.interface.readSliceShort(read_buffer[read_start_index..])) |bytes_read| {
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
                std.mem.copyForwards(u8, read_buffer[0..], read_buffer[line_start_index..]);
                line_end_index -= line_start_index;
                read_start_index = line_end_index;
                line_start_index = 0;
                continue :read_loop;
            };

            const line = read_buffer[line_start_index..line_end_index];
            if (std.mem.startsWith(u8, line, "SAO")) {
                if (parseStar(line)) |star| {
                    if (star.brightness > 0) {
                        try star_list.append(allocator, star);
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

    return try star_list.toOwnedSlice(allocator);
}

fn writeStarData(stars: []ExternStar, out_filename: []const u8) !void {
    var out_file = try std.fs.cwd().createFile(out_filename, .{});
    defer out_file.close();

    const bytes = std.mem.sliceAsBytes(stars);
    var writer = out_file.writer(&.{});
    try writer.interface.writeAll(bytes);

    try writer.interface.flush();
}

/// Read and parse all of the constellation files in a given directory.
fn readSkyFiles(allocator: Allocator, io: Io, constellation_dir_name: []const u8) ![]SkyFile {
    var sky_files: std.ArrayList(SkyFile) = .empty;
    errdefer sky_files.deinit(allocator);

    var constellation_dir = try std.fs.cwd().openDir(constellation_dir_name, .{ .iterate = true });
    defer constellation_dir.close();

    var constellation_dir_walker = try constellation_dir.walk(allocator);
    defer constellation_dir_walker.deinit();

    var read_buffer: [4096]u8 = undefined;

    var constellation_filenames: std.ArrayList([]const u8) = .empty;
    defer {
        for (constellation_filenames.items) |name| allocator.free(name);
        constellation_filenames.deinit(allocator);
    }

    while (try constellation_dir_walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".sky")) continue;

        const name_copy = try allocator.alloc(u8, entry.basename.len);
        @memcpy(name_copy, entry.basename);
        try constellation_filenames.append(allocator, name_copy);
    }

    const string_sort = (struct {
        fn sort(context: u32, lhs: []const u8, rhs: []const u8) bool {
            _ = context;

            return std.ascii.lessThanIgnoreCase(lhs, rhs);
        }
    }).sort;

    std.sort.insertion([]const u8, constellation_filenames.items, @as(u32, 0), string_sort);

    for (constellation_filenames.items) |basename| {
        var sky_file = try constellation_dir.openFile(basename, .{});
        defer sky_file.close();

        var reader = sky_file.reader(io, &.{});

        const bytes_read = try reader.interface.readSliceShort(read_buffer[0..]);

        const sky_file_data = try SkyFile.parse(allocator, read_buffer[0..bytes_read]);
        try sky_files.append(allocator, sky_file_data);
    }

    return try sky_files.toOwnedSlice(allocator);
}

fn writeConstellationData(sky_files: []SkyFile, out_filename: []const u8) !void {
    const cwd = fs.cwd();

    var out_file = try cwd.createFile(out_filename, .{});
    defer out_file.close();

    var writer = out_file.writer(&.{});

    var num_boundaries: u32 = 0;
    var num_asterisms: u32 = 0;
    for (sky_files) |sky_file| {
        num_boundaries += @as(u32, @intCast(sky_file.constellation.boundaries.len));
        num_asterisms += @as(u32, @intCast(sky_file.constellation.asterism.len));
    }

    _ = try writer.interface.write(std.mem.toBytes(@as(u32, @intCast(sky_files.len)))[0..]);
    _ = try writer.interface.write(std.mem.toBytes(num_boundaries)[0..]);
    _ = try writer.interface.write(std.mem.toBytes(num_asterisms)[0..]);

    for (sky_files) |sky_file| {
        const info = sky_file.constellation.getInfo();
        _ = try writer.interface.write(std.mem.toBytes(info)[0..]);
    }

    for (sky_files) |sky_file| {
        for (sky_file.constellation.boundaries) |boundary_coord| {
            _ = try writer.interface.write(std.mem.toBytes(boundary_coord)[0..]);
        }
    }

    for (sky_files) |sky_file| {
        for (sky_file.constellation.asterism) |asterism_coord| {
            _ = try writer.interface.write(std.mem.toBytes(asterism_coord)[0..]);
        }
    }

    try writer.interface.flush();
}

fn writeConstellationMetadata(sky_files: []SkyFile, filename: []const u8) !void {
    const cwd = fs.cwd();

    var out_file = try cwd.createFile(filename, .{});
    defer out_file.close();

    var writer = out_file.writer(&.{});

    try writer.interface.writeByte('[');
    for (sky_files, 0..) |sky_file, i| {
        try writer.interface.print("{{\"name\":\"{s}\",\"epithet\":\"{s}\"}}", .{ sky_file.name, sky_file.epithet });
        if (i < sky_files.len - 1) {
            try writer.interface.writeByte(',');
        }
    }
    try writer.interface.writeByte(']');

    try writer.interface.flush();
}
