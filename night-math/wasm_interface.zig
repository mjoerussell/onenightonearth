const std = @import("std");
const builtin = @import("builtin");

const log = @import("log.zig");

const Canvas = @import("Canvas.zig");
const Pixel = Canvas.Pixel;

const Point = @import("math_utils.zig").Point;

const StarRenderer = @import("StarRenderer.zig");

const Star = @import("Star.zig");
const ExternStar = Star.ExternStar;

const Constellation = @import("Constellation.zig");
const SkyCoord = @import("SkyCoord.zig");

const star_math = @import("star_math.zig");
const Coord = star_math.Coord;
const ObserverPosition = star_math.ObserverPosition;

const GreatCircle = @import("GreatCircle.zig");

const FixedPoint = @import("fixed_point.zig").DefaultFixedPoint;

const allocator = switch (builtin.cpu.arch) {
    .wasm32, .wasm64 => std.heap.wasm_allocator,
    else => std.heap.page_allocator,
};

const num_waypoints = 150;
var waypoints: [num_waypoints]Coord = undefined;

var result_data: []u8 = undefined;

const embeded_star_data align(@alignOf(ExternStar)) = @embedFile("star_data").*;
const embeded_const_data = @embedFile("const_data").*;

pub const ExternCanvasSettings = packed struct {
    width: u32,
    height: u32,
    background_radius: f32,
    zoom_factor: f32,
    drag_speed: f32,
    draw_north_up: u8,
    draw_constellation_grid: u8,
    draw_asterisms: u8,
    zodiac_only: u8,

    fn getCanvasSettings(self: ExternCanvasSettings) Canvas.Settings {
        return Canvas.Settings{
            .width = self.width,
            .height = self.height,
            .background_radius = self.background_radius,
            .zoom_factor = self.zoom_factor,
            .drag_speed = self.drag_speed,
            .draw_north_up = self.draw_north_up == 1,
            .draw_constellation_grid = self.draw_constellation_grid == 1,
            .draw_asterisms = self.draw_asterisms == 1,
            .zodiac_only = self.zodiac_only == 1,
        };
    }
};

pub fn initializeStars(star_renderer: *StarRenderer, stars: []const ExternStar) void {
    star_renderer.stars = std.MultiArrayList(Star){};
    star_renderer.stars.ensureTotalCapacity(allocator, embeded_star_data.len) catch {
        log.err("Ran out of memory trying to ensureCapacity to {} stars", .{stars.len});
        unreachable;
    };

    for (stars) |star| {
        star_renderer.stars.appendAssumeCapacity(star.toStar());
    }
}

pub export fn initialize(settings: *ExternCanvasSettings) *StarRenderer {
    var star_renderer = allocator.create(StarRenderer) catch @panic("OOM for StarRenderer");
    const stars = std.mem.bytesAsSlice(ExternStar, embeded_star_data[0..]);

    initializeStars(star_renderer, @alignCast(stars));

    star_renderer.canvas = Canvas.init(allocator, settings.getCanvasSettings()) catch @panic("OOM for Canvas");

    initializeConstellations(star_renderer, embeded_const_data[0..]);

    return star_renderer;
}

pub export fn updateCanvasSettings(star_renderer: *StarRenderer, settings: *ExternCanvasSettings) ?[*]u32 {
    const new_settings = settings.getCanvasSettings();
    if (new_settings.width != star_renderer.canvas.settings.width or new_settings.height != star_renderer.canvas.settings.height) {
        star_renderer.canvas.data = allocator.realloc(star_renderer.canvas.data, new_settings.width * new_settings.height) catch unreachable;
        star_renderer.canvas.settings = new_settings;
        return getImageData(star_renderer);
    }
    star_renderer.canvas.settings = new_settings;
    return null;
}

/// Initialize the result data slice - this will be used to "return" multiple results at once in functions like `getCoordForSkyCoord`.
pub export fn initializeResultData() [*]u8 {
    result_data = allocator.alloc(u8, 8) catch unreachable;
    return result_data.ptr;
}

/// Initialize the constellation boundaries, asterisms, and zodiac flags. Because each constellation has a variable number of boundaries and
/// asterisms, the data layout is slightly complicated.
/// Constellation data layout:
/// num_constellations | num_boundary_coords | num_asterism_coords | ...constellations | ...constellation_boundaries | ...constellation asterisms
/// constellations size = num_constellations * @sizeOf(ConstellationInfo)
/// constellation_boundaries size = num_boundary_coords * { i16, i16 }
/// constellation_asterisms size = num_asterism_coords * { i16, i16 }
pub fn initializeConstellations(star_renderer: *StarRenderer, data: []const u8) void {
    const ConstellationInfo = packed struct {
        num_boundaries: u8,
        num_asterisms: u8,
        is_zodiac: u8,
    };

    // Get some metadata about the constellation data that we're about to read.
    const num_constellations = std.mem.bytesToValue(u32, data[0..4]);
    const total_num_boundaries = std.mem.bytesToValue(u32, data[4..8]);

    const constellation_end_index: usize = @intCast(12 + num_constellations * @sizeOf(ConstellationInfo));
    const boundary_end_index: usize = @intCast(constellation_end_index + total_num_boundaries * @sizeOf(SkyCoord.ExternSkyCoord));

    // Convert the data slices from u8's to something more accurate. The constellation metadata is in the form of ConstellationInfo's,
    // and the boundary and asterism data are stored as i16 (fixed point) right ascension/declination pairs
    const constellation_data = std.mem.bytesAsSlice(ConstellationInfo, data[12..constellation_end_index]);
    const boundary_data = std.mem.bytesAsSlice(SkyCoord.ExternSkyCoord, data[constellation_end_index..boundary_end_index]);
    const asterism_data = std.mem.bytesAsSlice(SkyCoord.ExternSkyCoord, data[boundary_end_index..]);

    star_renderer.constellations = allocator.alloc(Constellation, num_constellations) catch @panic("OOM for constellations");

    // Initialize the actual constellation data
    var c_bound_start: usize = 0;
    var c_ast_start: usize = 0;
    for (star_renderer.constellations, 0..) |*c, c_index| {
        const num_boundaries = constellation_data[c_index].num_boundaries;
        const num_asterisms = constellation_data[c_index].num_asterisms;

        // Set up the constellation with empty boundaries and asterisms
        c.* = Constellation{
            .is_zodiac = constellation_data[c_index].is_zodiac == 1,
            .boundaries = allocator.alloc(SkyCoord, num_boundaries) catch unreachable,
            .asterism = allocator.alloc(SkyCoord, num_asterisms) catch unreachable,
        };

        // Get the correct boundary and asterism coords from the data slices
        for (c.boundaries, 0..) |*boundary, bound_index| {
            const bound_coord_index = c_bound_start + bound_index;
            boundary.* = boundary_data[bound_coord_index].toSkyCoord();
        }

        for (c.asterism, 0..) |*asterism, asterism_index| {
            const asterism_coord_index = c_ast_start + asterism_index;
            asterism.* = asterism_data[asterism_coord_index].toSkyCoord();
        }

        // Increment the base index for the boundaries and asterisms of the next constellation
        c_bound_start += num_boundaries;
        c_ast_start += num_asterisms;
    }
}

/// Returns a pointer to the pixel data so that it can be rendered on the canvas. Also sets the length of this buffer into the first slot
/// of result_data.
pub export fn getImageData(star_renderer: *StarRenderer) [*]u32 {
    setResult(@as(u32, @intCast(star_renderer.canvas.data.len)) * 4, 0);
    return star_renderer.canvas.data.ptr;
}

/// Clear the canvas pixel data.
pub export fn resetImageData(star_renderer: *StarRenderer) void {
    star_renderer.canvas.resetImageData();
}

/// The main rendering function. This will render all of the stars and, if turned on, the constellation asterisms and/or boundaries.
pub export fn projectStarsAndConstellations(star_renderer: *StarRenderer, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    star_renderer.run(observer_latitude, observer_longitude, observer_timestamp);
}

/// Given a point on the canvas, determine which constellation (if any (but there should always be one)) is currently at that point. Once
/// the constellation is found, draw a thicker line over that constellation's boundary and/or asterism to highlight it.
/// Finally, return the index of the constellation so that the JS part of the frontend can show the constellation info.
pub export fn getConstellationAtPoint(star_renderer: *StarRenderer, x: f32, y: f32, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) isize {
    const point = Point{ .x = x, .y = y };

    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const local_sidereal_time = pos.localSiderealTime();
    const sin_lat = std.math.sin(observer_latitude);
    const cos_lat = std.math.cos(observer_latitude);

    const index = star_math.getConstellationAtPoint(star_renderer.canvas, point, star_renderer.constellations, local_sidereal_time, sin_lat, cos_lat);
    if (index) |i| {
        if (star_renderer.canvas.settings.draw_constellation_grid) {
            star_renderer.canvas.drawGrid(star_renderer.constellations[i], Pixel.rgb(255, 255, 255), 3, local_sidereal_time, sin_lat, cos_lat);
        }
        if (star_renderer.canvas.settings.draw_asterisms) {
            star_renderer.canvas.drawAsterism(star_renderer.constellations[i], Pixel.rgb(255, 255, 255), 3, local_sidereal_time, sin_lat, cos_lat);
        }
        return @as(isize, @intCast(i));
    } else return -1;
}

/// Compute a new coordiate based on the mouse drag state. Sets the latitude and longitude of the new coordinate into the respective slots of
/// `result_data`.
pub export fn dragAndMove(star_renderer: *StarRenderer, drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) void {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y, star_renderer.canvas.settings.drag_speed);
    setResult(coord.latitude, coord.longitude);
}

/// Compute waypoints between two coordinates. Returns a pointer to the waypoints, but does not allocate any
/// new memory.
pub export fn findWaypoints(start_lat: f32, start_long: f32, end_lat: f32, end_long: f32) [*]Coord {
    const start = Coord{ .latitude = start_lat, .longitude = start_long };
    const end = Coord{ .latitude = end_lat, .longitude = end_long };

    const great_circle = GreatCircle.init(start, end);
    var waypoint_iter = great_circle.getWaypoints(num_waypoints);

    var waypoint_index: usize = 0;
    while (waypoint_iter.next()) |waypoint| : (waypoint_index += 1) {
        waypoints[waypoint_index] = waypoint;
    }

    return &waypoints;
}

/// Given a sky coordinate and a timestamp, compute the Earth coordinate currently "below" that position. Puts the latitude and
/// longitude into the result_data buffer.
pub export fn getCoordForSkyCoord(right_ascension: f32, declination: f32, observer_timestamp: i64) void {
    const sky_coord = SkyCoord{ .right_ascension = right_ascension, .declination = declination };
    const coord = sky_coord.getCoord(observer_timestamp);
    setResult(coord.latitude, coord.longitude);
}

/// Get the central point of a given constellation. This point may be outside of the boundaries of a constellation if the constellation is
/// irregularly shaped. The point is selected to make the constellation centered in the canvas.
pub export fn getConstellationCentroid(star_renderer: *StarRenderer, constellation_index: u32) void {
    const centroid = if (constellation_index > star_renderer.constellations.len) SkyCoord{} else star_renderer.constellations[@as(usize, @intCast(constellation_index))].centroid();
    setResult(centroid.right_ascension, centroid.declination);
}

/// Set data in the result buffer so that it can be read in the JS side. Both values must be exactly 4 bytes long.
fn setResult(a: anytype, b: @TypeOf(a)) void {
    const A = @TypeOf(a);
    comptime if (@sizeOf(A) != 4) @compileError("Result data must be exactly 4 bytes each");
    const result_ptr = @as([*]A, @ptrCast(@alignCast(result_data.ptr)));
    result_ptr[0] = a;
    result_ptr[1] = b;
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
