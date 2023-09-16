const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const fp = @import("fixed_point.zig");
const FixedPoint = fp.FixedPoint(i16, 12);

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

pub const SpectralType = enum(u8) {
    O,
    B,
    A,
    F,
    G,
    K,
    M,

    pub fn fromChar(char: u8) ?SpectralType {
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
};

pub const SkyCoord = packed struct {
    right_ascension: i16,
    declination: i16,
};

pub const ConstellationInfo = packed struct {
    num_boundaries: u8,
    num_asterisms: u8,
    is_zodiac: u8,
};

pub const Constellation = struct {
    name: []const u8,
    epithet: []const u8,
    boundaries: []SkyCoord,
    asterism: []SkyCoord,
    is_zodiac: bool = false,

    pub fn deinit(self: *Constellation, allocator: Allocator) void {
        allocator.free(self.boundaries);
        allocator.free(self.asterism);
        allocator.free(self.name);
        allocator.free(self.epithet);
    }

    pub fn getInfo(self: Constellation) ConstellationInfo {
        return .{ .num_boundaries = @as(u8, @intCast(self.boundaries.len)), .num_asterisms = @as(u8, @intCast(self.asterism.len)), .is_zodiac = if (self.is_zodiac) @as(u8, 1) else @as(u8, 0) };
    }

    pub fn parseSkyFile(allocator: Allocator, data: []const u8) !Constellation {
        const ParseState = enum {
            stars,
            asterism,
            boundaries,
        };

        var constellation: Constellation = undefined;
        constellation.is_zodiac = false;

        var stars = std.StringHashMap(SkyCoord).init(allocator);
        defer stars.deinit();

        var boundary_list = std.ArrayList(SkyCoord).init(allocator);
        errdefer boundary_list.deinit();

        var asterism_list = std.ArrayList(SkyCoord).init(allocator);
        errdefer asterism_list.deinit();

        var line_iter = std.mem.split(u8, data, "\r\n");

        var parse_state: ParseState = .stars;

        while (line_iter.next()) |line| {
            if (std.mem.trim(u8, line, " ").len == 0) continue;

            if (std.mem.indexOf(u8, line, "#zodiac")) |_| {
                constellation.is_zodiac = true;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@name")) |_| {
                var line_split = std.mem.split(u8, line, "=");
                _ = line_split.next();
                const name = line_split.next().?;
                const trimmed_name = std.mem.trim(u8, name, " ");
                var name_copy = try allocator.alloc(u8, trimmed_name.len);
                std.mem.copy(u8, name_copy, trimmed_name);
                constellation.name = name_copy;
                continue;
            }

            if (std.mem.indexOf(u8, line, "@epithet")) |_| {
                var line_split = std.mem.split(u8, line, "=");
                _ = line_split.next();
                const epithet = line_split.next().?;
                const trimmed_epithet = std.mem.trim(u8, epithet, " ");
                var epithet_copy = try allocator.alloc(u8, trimmed_epithet.len);
                std.mem.copy(u8, epithet_copy, trimmed_epithet);
                constellation.epithet = epithet_copy;
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
                        var parts = std.mem.split(u8, line, ",");
                        const star_name = std.mem.trim(u8, parts.next().?, " ");
                        const right_ascension = std.mem.trim(u8, parts.next().?, " ");
                        const declination = std.mem.trim(u8, parts.next().?, " ");

                        var ra_value = try std.fmt.parseFloat(f32, right_ascension);
                        var dec_value = try std.fmt.parseFloat(f32, declination);

                        const star_coord = SkyCoord{
                            .right_ascension = FixedPoint.fromFloat(degToRadLong(ra_value)),
                            .declination = FixedPoint.fromFloat(degToRad(dec_value)),
                        };

                        try stars.put(star_name, star_coord);
                    },
                    .asterism => {
                        var parts = std.mem.split(u8, line, ",");
                        const star_a_name = std.mem.trim(u8, parts.next().?, " ");
                        const star_b_name = std.mem.trim(u8, parts.next().?, " ");

                        if (stars.get(star_a_name)) |star_a| {
                            if (stars.get(star_b_name)) |star_b| {
                                try asterism_list.append(star_a);
                                try asterism_list.append(star_b);
                            }
                        }
                    },
                    .boundaries => {
                        var parts = std.mem.split(u8, line, ",");
                        const right_ascension_long = std.mem.trim(u8, parts.next().?, " ");
                        const declination = std.mem.trim(u8, parts.next().?, " ");

                        var right_ascension_parts = std.mem.split(u8, right_ascension_long, " ");
                        const ra_hours = try std.fmt.parseInt(u32, right_ascension_parts.next().?, 10);
                        const ra_minutes = try std.fmt.parseInt(u32, right_ascension_parts.next().?, 10);
                        const ra_seconds = try std.fmt.parseFloat(f32, right_ascension_parts.next().?);

                        const right_ascension = @as(f32, @floatFromInt(ra_hours * 15)) + ((@as(f32, @floatFromInt(ra_minutes)) / 60) * 15) + ((ra_seconds / 3600) * 15);
                        const dec_value = try std.fmt.parseFloat(f32, std.mem.trim(u8, declination, " "));
                        var boundary_coord = SkyCoord{
                            .right_ascension = FixedPoint.fromFloat(degToRadLong(right_ascension)),
                            .declination = FixedPoint.fromFloat(degToRad(dec_value)),
                        };

                        try boundary_list.append(boundary_coord);
                    },
                }
            }
        }

        constellation.boundaries = try boundary_list.toOwnedSlice();
        constellation.asterism = try asterism_list.toOwnedSlice();

        return constellation;
    }
};

pub const Star = packed struct {
    right_ascension: i16,
    declination: i16,
    brightness: u8,
    spec_type: SpectralType,

    fn parse(data: []const u8) !Star {
        var star: Star = undefined;

        var parts_iter = std.mem.split(u8, data, "|");
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
                    star.spec_type = SpectralType.fromChar(part[0]) orelse .A;
                },
                else => {},
            }
        }

        star.right_ascension = FixedPoint.fromFloat(degToRadLong(right_ascension));
        star.declination = FixedPoint.fromFloat(degToRad(declination));

        return star;
    }
};

const Arguments = struct {
    const SourceDest = struct {
        source: []const u8,
        dest: []const u8,
    };

    /// Controls the generation of star coordinates. Expects a path to the sao_catalog file as the source.
    stars: ?SourceDest = null,
    constellations: ?SourceDest = null,
    metadata: ?SourceDest = null,

    pub fn init(args: []const []const u8) !Arguments {
        var arguments = Arguments{};

        var arg_index: usize = 0;
        while (arg_index < args.len) : (arg_index += 1) {
            inline for (@typeInfo(Arguments).Struct.fields) |field| {
                const arg_name = "--" ++ field.name;
                if (std.mem.eql(u8, args[arg_index], arg_name)) {
                    if (args.len < arg_index + 2) {
                        log.err("Wrong number of arguments provided for " ++ arg_name, .{});
                        return error.MissingArguments;
                    }

                    @field(arguments, field.name) = SourceDest{
                        .source = args[arg_index + 1],
                        .dest = args[arg_index + 2],
                    };

                    arg_index += 2;
                }
            }
        }

        return arguments;
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const arguments = try Arguments.init(args);

    if (arguments.stars) |star_args| {
        std.debug.print("Generating star data: {s} -> {s}\n", .{ star_args.source, star_args.dest });
        var stars = try readSaoCatalog(allocator, star_args.source);
        try writeStarData(stars, star_args.dest);
    }

    if (arguments.constellations) |const_args| {
        std.debug.print("Generating constellation data: {s} -> {s}\n", .{ const_args.source, const_args.dest });
        const constellations = try readConstellationFiles(allocator, const_args.source);
        defer {
            for (constellations) |*c| c.deinit(allocator);
            allocator.free(constellations);
        }

        try writeConstellationData(constellations, const_args.dest);
    }

    if (arguments.metadata) |meta_args| {
        log.info("Generating constellation metadata: {s} -> {s}", .{ meta_args.source, meta_args.dest });
        const constellations = try readConstellationFiles(allocator, meta_args.source);
        defer {
            for (constellations) |*c| c.deinit(allocator);
            allocator.free(constellations);
        }
        try writeConstellationMetadata(allocator, constellations, meta_args.dest);
    }
}

fn readSaoCatalog(allocator: Allocator, catalog_filename: []const u8) ![]Star {
    const cwd = fs.cwd();
    const sao_catalog = try cwd.openFile(catalog_filename, .{});
    defer sao_catalog.close();

    var star_list = try std.ArrayList(Star).initCapacity(allocator, 75000);
    errdefer star_list.deinit();

    var read_buffer: [std.mem.page_size]u8 = undefined;
    var read_start_index: usize = 0;
    var line_start_index: usize = 0;
    var line_end_index: usize = 0;

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
                    if (star.brightness > 0) {
                        try star_list.append(star);
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

    return try star_list.toOwnedSlice();
}

fn writeStarData(stars: []Star, out_filename: []const u8) !void {
    const cwd = fs.cwd();

    var out_file = try cwd.createFile(out_filename, .{});
    defer out_file.close();

    var out_file_writer = out_file.writer();
    var buffered_writer = std.io.bufferedWriter(out_file_writer);

    var writer = buffered_writer.writer();

    var bytes = std.mem.sliceAsBytes(stars);
    _ = try writer.write(bytes);

    try buffered_writer.flush();
}

/// Read and parse all of the constellation files in a given directory.
fn readConstellationFiles(allocator: Allocator, constellation_dir_name: []const u8) ![]Constellation {
    var constellations = std.ArrayList(Constellation).init(allocator);
    errdefer constellations.deinit();

    const cwd = fs.cwd();
    var constellation_dir = try cwd.openIterableDir(constellation_dir_name, .{});
    defer constellation_dir.close();

    var constellation_dir_walker = try constellation_dir.walk(allocator);
    defer constellation_dir_walker.deinit();

    var read_buffer: [4096]u8 = undefined;

    var constellation_filenames = std.ArrayList([]const u8).init(allocator);
    defer {
        for (constellation_filenames.items) |name| allocator.free(name);
        constellation_filenames.deinit();
    }

    while (try constellation_dir_walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".sky")) continue;

        var name_copy = try allocator.alloc(u8, entry.basename.len);
        std.mem.copy(u8, name_copy, entry.basename);
        try constellation_filenames.append(name_copy);
    }

    const string_sort = (struct {
        fn sort(context: u32, lhs: []const u8, rhs: []const u8) bool {
            _ = context;

            return std.ascii.lessThanIgnoreCase(lhs, rhs);
        }
    }).sort;

    std.sort.insertion([]const u8, constellation_filenames.items, @as(u32, 0), string_sort);

    for (constellation_filenames.items) |basename| {
        var sky_file = try constellation_dir.dir.openFile(basename, .{});
        defer sky_file.close();

        const bytes_read = try sky_file.readAll(read_buffer[0..]);

        const constellation = try Constellation.parseSkyFile(allocator, read_buffer[0..bytes_read]);
        try constellations.append(constellation);
    }

    return try constellations.toOwnedSlice();
}

fn writeConstellationData(constellations: []Constellation, out_filename: []const u8) !void {
    const cwd = fs.cwd();

    var out_file = try cwd.createFile(out_filename, .{});
    defer out_file.close();

    var out_file_writer = out_file.writer();
    var buffered_writer = std.io.bufferedWriter(out_file_writer);

    var writer = buffered_writer.writer();

    var num_boundaries: u32 = 0;
    var num_asterisms: u32 = 0;
    for (constellations) |constellation| {
        num_boundaries += @as(u32, @intCast(constellation.boundaries.len));
        num_asterisms += @as(u32, @intCast(constellation.asterism.len));
    }

    _ = try writer.write(std.mem.toBytes(@as(u32, @intCast(constellations.len)))[0..]);
    _ = try writer.write(std.mem.toBytes(num_boundaries)[0..]);
    _ = try writer.write(std.mem.toBytes(num_asterisms)[0..]);

    for (constellations) |constellation| {
        const info = constellation.getInfo();
        _ = try writer.write(std.mem.toBytes(info)[0..]);
    }

    for (constellations) |constellation| {
        for (constellation.boundaries) |boundary_coord| {
            _ = try writer.write(std.mem.toBytes(boundary_coord)[0..]);
        }
    }

    for (constellations) |constellation| {
        for (constellation.asterism) |asterism_coord| {
            _ = try writer.write(std.mem.toBytes(asterism_coord)[0..]);
        }
    }

    try buffered_writer.flush();
}

fn writeConstellationMetadata(allocator: Allocator, constellations: []Constellation, filename: []const u8) !void {
    const cwd = fs.cwd();

    var out_file = try cwd.createFile(filename, .{});
    defer out_file.close();

    var out_file_writer = out_file.writer();
    var buffered_writer = std.io.bufferedWriter(out_file_writer);

    var writer = buffered_writer.writer();

    var metadata_json = std.ArrayList(std.json.Value).init(allocator);
    for (constellations) |constellation| {
        var c_map = std.json.ObjectMap.init(allocator);
        try c_map.putNoClobber("name", std.json.Value{ .string = constellation.name });
        try c_map.putNoClobber("epithet", std.json.Value{ .string = constellation.epithet });

        const val = std.json.Value{ .object = c_map };
        try metadata_json.append(val);
    }
    const metadata = std.json.Value{ .array = metadata_json };

    try std.json.stringify(metadata, .{}, writer);

    try buffered_writer.flush();
}
