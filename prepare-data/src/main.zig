const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

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
};

pub const SkyCoord = packed struct {
    right_ascension: f32,
    declination: f32,
};

pub const ConstellationInfo = packed struct {
    num_boundaries: u32,
    num_asterisms: u32,
    is_zodiac: u8,
};

pub const Constellation = struct {
    boundaries: []SkyCoord,
    asterism: []SkyCoord,
    is_zodiac: bool = false,

    pub fn deinit(self: *Constellation, allocator: *Allocator) void {
        allocator.free(self.boundaries);
        allocator.free(self.asterism);
    }

    pub fn getInfo(self: Constellation) ConstellationInfo {
        return .{
            .num_boundaries = @intCast(u32, self.boundaries.len),
            .num_asterisms = @intCast(u32, self.asterism.len),
            .is_zodiac = if (self.is_zodiac) @as(u8, 1) else @as(u8, 0)
        };
    }

    pub fn parseSkyFile(allocator: *Allocator, data: []const u8) !Constellation {
        const ParseState = enum {
            stars,
            asterism,
            boundaries,
        };

        var stars = std.StringHashMap(SkyCoord).init(allocator);
        defer stars.deinit();

        var boundary_list = std.ArrayList(SkyCoord).init(allocator);
        errdefer boundary_list.deinit();
        
        var asterism_list = std.ArrayList(SkyCoord).init(allocator);
        errdefer asterism_list.deinit();

        var is_zodiac = false;

        var line_iter = std.mem.split(u8, data, "\r\n");

        var parse_state: ParseState = .stars;

        while (line_iter.next()) |line| {
            if (std.mem.trim(u8, line, " ").len == 0) continue;

            if (std.mem.indexOf(u8, line, "#zodiac")) |_| {
                is_zodiac = true;
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

                        var star_coord = SkyCoord{ 
                            .right_ascension = try std.fmt.parseFloat(f32, right_ascension), 
                            .declination = try std.fmt.parseFloat(f32, declination)
                        };

                        star_coord.right_ascension = degToRad(star_coord.right_ascension);
                        star_coord.declination = degToRad(star_coord.declination);

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

                        const right_ascension = @intToFloat(f32, ra_hours * 15) + ((@intToFloat(f32, ra_minutes) / 60) * 15) + ((ra_seconds / 3600) * 15);

                        var boundary_coord = SkyCoord{
                            .right_ascension = right_ascension,
                            .declination = try std.fmt.parseFloat(f32, std.mem.trim(u8, declination, " ")),
                        };

                        boundary_coord.right_ascension = degToRad(boundary_coord.right_ascension);
                        boundary_coord.declination = degToRad(boundary_coord.declination);

                        try boundary_list.append(boundary_coord);
                    },
                }
            }
        }

        return Constellation{
            .boundaries = boundary_list.toOwnedSlice(),
            .asterism = asterism_list.toOwnedSlice(),
            .is_zodiac = is_zodiac,
        };
    }
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

        star.right_ascension = degToRad(star.right_ascension);
        star.declination = degToRad(star.declination);

        return star;
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.log.err("Must provide an output file name for both outputs", .{});
        return error.InvalidArgs;
    }

    const star_out_filename = args[1];
    const const_out_filename = args[2];

    var timer = std.time.Timer.start() catch unreachable;
    const start = timer.read();

    var stars = try readSaoCatalog(allocator, "sao_catalog");

    const end = timer.read();
    std.debug.print("Parsing took {d:.4} ms\n", .{(end - start) / 1_000_000});

    var shuffle_count: usize = 0;
    while (shuffle_count < 1000) : (shuffle_count += 1) {
        shuffleStars(stars);
    }

    try writeStarData(stars, star_out_filename);

    const constellations = try readConstellationFiles(allocator, "constellations/iau");
    defer {
        for (constellations) |*c| c.deinit(allocator);
        allocator.free(constellations);
    }

    try writeConstellationData(constellations, const_out_filename);
}

fn readSaoCatalog(allocator: *Allocator, catalog_filename: []const u8) ![]Star {
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
                    if (star.brightness >= 0.3) {
                        star_list.appendAssumeCapacity(star);
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

    std.debug.print("Wrote {} stars\n", .{star_list.items.len});
    return star_list.toOwnedSlice();
}

fn writeStarData(stars: []Star, out_filename: []const u8) !void {
    const cwd = fs.cwd();

    const output_file = try cwd.createFile(out_filename, .{});
    defer output_file.close();

    var output_buffered_writer = std.io.bufferedWriter(output_file.writer());
    var output_writer = output_buffered_writer.writer();

    for (stars) |star| {
        try output_writer.writeAll(std.mem.toBytes(star)[0..]);
    }

    try output_buffered_writer.flush();
}

/// Read and parse all of the constellation files in a given directory.
fn readConstellationFiles(allocator: *Allocator, constellation_dir_name: []const u8) ![]Constellation {
    var constellations = std.ArrayList(Constellation).init(allocator);
    errdefer constellations.deinit();

    const cwd = fs.cwd();
    var constellation_dir = try cwd.openDir(constellation_dir_name, .{ .iterate = true });
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
        if (entry.kind != .File) continue;
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

    std.sort.sort([]const u8, constellation_filenames.items, @as(u32, 0), string_sort);

    for (constellation_filenames.items) |basename| {
        var sky_file = try constellation_dir.openFile(basename, .{});
        defer sky_file.close();

        const bytes_read = try sky_file.readAll(read_buffer[0..]);

        const constellation = try Constellation.parseSkyFile(allocator, read_buffer[0..bytes_read]);
        try constellations.append(constellation);
    }

    return constellations.toOwnedSlice();
}

fn writeConstellationData(constellations: []Constellation, const_out_filename: []const u8) !void {
    const cwd = fs.cwd();
    const constellation_out_file = try cwd.createFile(const_out_filename, .{});
    defer constellation_out_file.close();

    var const_out_buffered_writer = std.io.bufferedWriter(constellation_out_file.writer());
    var const_out_writer = const_out_buffered_writer.writer();
    
    var num_boundaries: u32 = 0;
    var num_asterisms: u32 = 0;
    for (constellations) |constellation| {
        num_boundaries += @intCast(u32, constellation.boundaries.len);
        num_asterisms += @intCast(u32, constellation.asterism.len);
    }

    try const_out_writer.writeAll(std.mem.toBytes(@intCast(u32, constellations.len))[0..]);
    try const_out_writer.writeAll(std.mem.toBytes(num_boundaries)[0..]);
    try const_out_writer.writeAll(std.mem.toBytes(num_asterisms)[0..]);

    for (constellations) |constellation| {
        const info = constellation.getInfo();
        try const_out_writer.writeAll(std.mem.toBytes(info)[0..]);
    }

    for (constellations) |constellation| {
        for (constellation.boundaries) |boundary_coord| {
            try const_out_writer.writeAll(std.mem.toBytes(boundary_coord)[0..]);
        }
    }
    
    for (constellations) |constellation| {
        for (constellation.asterism) |asterism_coord| {
            try const_out_writer.writeAll(std.mem.toBytes(asterism_coord)[0..]);
        }
    }

    try const_out_buffered_writer.flush();
}

/// Randomize the order of the stars. This is so that, when the star data starts streaming in when the page begins loading, the
/// stars populate in the sky in a natural-feeling way. Without this, stars would fill the canvas in a roughly bottom-up way.
fn shuffleStars(stars: []Star) void {
    const timer = std.time.Timer.start() catch unreachable;
    var rand = std.rand.DefaultPrng.init(timer.read());

    const fold_range_size = stars.len / 6;

    const fold_low_start = rand.random.intRangeAtMost(usize, 0, stars.len / 2);
    const fold_high_start = rand.random.intRangeAtMost(usize, stars.len / 2, stars.len - fold_range_size);

    var fold_index: usize = 0;
    while (fold_index <= fold_range_size) : (fold_index += 1) {
        const fold_low_index = fold_low_start + fold_index;
        const fold_high_index = fold_high_start + fold_index;
        std.mem.swap(Star, &stars[fold_low_index], &stars[fold_high_index]);
    }

    var low_index: usize = 0;
    var high_index: usize = stars.len - 1;
    while (low_index < high_index) : ({ low_index += 1; high_index -= 1; }) {
        const low_bias: isize = rand.random.intRangeLessThan(isize, -5, 5);
        const high_bias: isize = rand.random.intRangeLessThan(isize, -5, 5);

        const low_swap_index = if (@intCast(isize, low_index) + low_bias < 0) 
            low_index
        else
            @intCast(usize, @intCast(isize, low_index) + low_bias);

        const high_swap_index = if (@intCast(isize, high_index) + high_bias >= stars.len) 
            high_index
        else
            @intCast(usize, @intCast(isize, high_index) + high_bias);

        std.mem.swap(Star, &stars[low_swap_index], &stars[high_swap_index]);
    }

}
