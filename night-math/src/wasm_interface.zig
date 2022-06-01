const std = @import("std");

const log = @import("./log.zig");

const Canvas = @import("./Canvas.zig");
const Pixel = Canvas.Pixel;

const Point = @import("./math_utils.zig").Point;

const StarRenderer = @import("./StarRenderer.zig");

const Star = @import("Star.zig");
const ExternStar = Star.ExternStar;

const star_math = @import("./star_math.zig");
const Constellation = star_math.Constellation;
const SkyCoord = star_math.SkyCoord;
const Coord = star_math.Coord;
const ObserverPosition = star_math.ObserverPosition;
const GreatCircle = star_math.GreatCircle;

const fixed_point = @import("fixed_point.zig");
const FixedPoint = fixed_point.FixedPoint(i16, 12);

const allocator = std.heap.page_allocator;

const num_waypoints = 150;
var waypoints: [num_waypoints]Coord = undefined;

var result_data: []u8 = undefined;

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

pub fn initializeStars(star_renderer: *StarRenderer, stars: []ExternStar) void {
    star_renderer.stars = std.MultiArrayList(Star){};
    star_renderer.stars.ensureTotalCapacity(allocator, stars.len) catch {
        log.err("Ran out of memory trying to ensureCapacity to {} stars", .{stars.len});
        unreachable;
    };

    for (stars) |star| {
        star_renderer.stars.appendAssumeCapacity(Star.fromExternStar(star));
    }

    allocator.free(stars);
}

pub export fn initialize(stars: [*]ExternStar, num_stars: u32, constellation_data: [*]u8, settings: *ExternCanvasSettings) *StarRenderer {
    var star_renderer = allocator.create(StarRenderer) catch {
        log.err("Could not create StarRenderer, needs {} bytes", .{@sizeOf(StarRenderer)});
        unreachable;
    };
    initializeStars(star_renderer, stars[0..num_stars]);
    
    star_renderer.canvas = Canvas.init(allocator, settings.getCanvasSettings()) catch {
        const num_pixels = star_renderer.canvas.settings.width * star_renderer.canvas.settings.height;
        log.err("Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
        unreachable;
    };

    initializeConstellations(star_renderer, constellation_data);
    
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
pub fn initializeConstellations(star_renderer: *StarRenderer, data: [*]u8) void {
    // Constellation data layout:
    // num_constellations | num_boundary_coords | num_asterism_coords | ...constellations | ...constellation_boundaries | ...constellation asterisms
    // constellations size = num_constellations * { u8 u8 u8 } (num boundaries, num asterisms, is_zodiac)
    // constellation_boundaries size = num_boundary_coords * { f32 f32 }
    // constellation_asterisms size = num_asterism_coords * { f32 f32 }
    const ConstellationInfo = packed struct {
        num_boundaries: u8,
        num_asterisms: u8,
        is_zodiac: u8,
    };

    const num_constellations = std.mem.bytesToValue(u32, data[0..4]);
    const num_boundaries = std.mem.bytesToValue(u32, data[4..8]);
    const num_asterisms = std.mem.bytesToValue(u32, data[8..12]);

    const constellation_end_index = @intCast(usize, 12 + num_constellations * @sizeOf(ConstellationInfo));
    const boundary_end_index = @intCast(usize, constellation_end_index + num_boundaries * @sizeOf(SkyCoord));
    const asterism_end_index = @intCast(usize, boundary_end_index + num_asterisms * @sizeOf(SkyCoord));

    const constellation_data = @ptrCast([*]ConstellationInfo, data[12..constellation_end_index])[0..num_constellations];
    const boundary_data = @ptrCast([*]SkyCoord, data[constellation_end_index..boundary_end_index])[0..num_boundaries];
    const asterism_data = @ptrCast([*]SkyCoord, data[boundary_end_index..asterism_end_index])[0..num_asterisms];

    star_renderer.constellations = allocator.alloc(Constellation, num_constellations) catch {
        log.err("Error while allocating constellations: tried to allocate {} constellations\n", .{num_constellations});
        unreachable;
    };

    var c_bound_start: usize = 0;
    var c_ast_start: usize = 0;
    for (star_renderer.constellations) |*c, c_index| {
        c.* = Constellation{
            .is_zodiac = constellation_data[c_index].is_zodiac == 1,
            .boundaries = boundary_data[c_bound_start..c_bound_start + constellation_data[c_index].num_boundaries],
            .asterism = asterism_data[c_ast_start..c_ast_start + constellation_data[c_index].num_asterisms],
        };
        c_bound_start += constellation_data[c_index].num_boundaries;
        c_ast_start += constellation_data[c_index].num_asterisms;
    }
}

/// Returns a pointer to the pixel data so that it can be rendered on the canvas. Also sets the length of this buffer into the first slot
/// of result_data.
pub export fn getImageData(star_renderer: *StarRenderer) [*]u32 {
    setResult(@intCast(u32, star_renderer.canvas.data.len) * 4, 0);
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

    const index = star_math.getConstellationAtPoint(&star_renderer.canvas, point, star_renderer.constellations, local_sidereal_time, sin_lat, cos_lat);
    if (index) |i| {
        if (star_renderer.canvas.settings.draw_constellation_grid) {
            star_renderer.canvas.drawGrid(star_renderer.constellations[i], Pixel.rgb(255, 255, 255), 3, local_sidereal_time, sin_lat, cos_lat);
        }
        if (star_renderer.canvas.settings.draw_asterisms) {
            star_renderer.canvas.drawAsterism(star_renderer.constellations[i], Pixel.rgb(255, 255, 255), 3, local_sidereal_time, sin_lat, cos_lat);
        }
        return @intCast(isize, i);
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

    const great_circle = GreatCircle(num_waypoints).init(start, end);

    std.mem.copy(Coord, waypoints[0..], great_circle.waypoints[0..]);

    return &waypoints;
}

/// Given a sky coordinate and a timestamp, compute the Earth coordinate currently "below" that position. Puts the latitude and
/// longitude into the result_data buffer.
pub export fn getCoordForSkyCoord(right_ascension: f32, declination: f32, observer_timestamp: i64) void {
    const sky_coord = SkyCoord{ .right_ascension = FixedPoint.fromFloat(right_ascension), .declination = FixedPoint.fromFloat(declination) };
    const coord = sky_coord.getCoord(observer_timestamp);
    setResult(coord.latitude, coord.longitude);
}

/// Get the central point of a given constellation. This point may be outside of the boundaries of a constellation if the constellation is
/// irregularly shaped. The point is selected to make the constellation centered in the canvas.
pub export fn getConstellationCentroid(star_renderer: *StarRenderer, constellation_index: u32) void {
    const centroid = if (constellation_index > star_renderer.constellations.len) SkyCoord{} else star_renderer.constellations[@intCast(usize, constellation_index)].centroid();
    setResult(FixedPoint.toFloat(centroid.right_ascension), FixedPoint.toFloat(centroid.declination));
}

/// Set data in the result buffer so that it can be read in the JS side. Both values must be exactly 4 bytes long.
fn setResult(a: anytype, b: @TypeOf(a)) void {
    const A = @TypeOf(a);
    comptime if (@sizeOf(A) != 4) @compileError("Result data must be exactly 4 bytes each");
    const result_ptr = @ptrCast([*]A, @alignCast(@alignOf(A), result_data.ptr));
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
