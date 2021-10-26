const std = @import("std");
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;

const log = @import("./log.zig").log;

const render = @import("./render.zig");
const Canvas = render.Canvas;
const Pixel = render.Pixel;

const math_utils = @import("./math_utils.zig");
const Point = math_utils.Point;

const star_math = @import("./star_math.zig");
const Star = star_math.Star;
const Constellation = star_math.Constellation;
const SkyCoord = star_math.SkyCoord;
const Coord = star_math.Coord;
const ObserverPosition = star_math.ObserverPosition;
const GreatCircle = star_math.GreatCircle;

const allocator = std.heap.page_allocator;

var canvas: Canvas = undefined;
var stars: []Star = undefined;
var waypoints: []Coord = undefined;
const num_waypoints = 150;

var constellations: []Constellation = undefined;

var result_data: []u8 = undefined;

const ExternCanvasSettings = packed struct {
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

pub export fn allocateStars(num_stars: u32) [*]Star {
    stars = allocator.alloc(Star, @intCast(usize, num_stars)) catch unreachable;
    waypoints = allocator.alloc(Coord, num_waypoints) catch unreachable;
    return stars.ptr;
}

pub export fn initializeCanvas(settings: *ExternCanvasSettings) void {
    canvas = Canvas.init(allocator, settings.getCanvasSettings()) catch {
        const num_pixels = canvas.settings.width * canvas.settings.height;
        log(.Error, "Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
        unreachable;
    };
}

// Format:
// num_constellations | num_boundary_coords | num_asterism_coords | ...constellations | ...constellation_boundaries | ...constellation asterisms
// constellations size = num_constellations * { f32 f32 u8 }
// constellation_boundaries size = num_boundary_coords * { f32 f32 }
// constellation_asterisms size = num_asterism_coords * { f32 f32 }

pub export fn initializeConstellations(data: [*]u8) void {
    const ConstellationInfo = packed struct {
        num_boundaries: u32,
        num_asterisms: u32,
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

    constellations = allocator.alloc(Constellation, num_constellations) catch {
        log(.Error, "Error while allocating constellations: tried to allocate {} constellations\n", .{num_constellations});
        unreachable;
    };

    var c_bound_start: usize = 0;
    var c_ast_start: usize = 0;
    for (constellations) |*c, c_index| {
        c.* = Constellation{
            .is_zodiac = constellation_data[c_index].is_zodiac != 0,
            .boundaries = boundary_data[c_bound_start..c_bound_start + constellation_data[c_index].num_boundaries],
            .asterism = asterism_data[c_ast_start..c_ast_start + constellation_data[c_index].num_asterisms],
        };
        c_bound_start += constellation_data[c_index].num_boundaries;
        c_ast_start += constellation_data[c_index].num_asterisms;
    }
}

pub export fn updateCanvasSettings(settings: *ExternCanvasSettings) void {
    canvas.settings = settings.getCanvasSettings();
}

pub export fn getImageData(size_in_bytes: *u32) [*]Pixel {
    size_in_bytes.* = @intCast(u32, canvas.data.len * @sizeOf(Pixel));
    return canvas.data.ptr;
}

pub export fn resetImageData() void {
    for (canvas.data) |*p| {
        p.* = Pixel{};
    }   
}

pub export fn projectStars(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    for (stars) |star| {
        star_math.projectStar(&canvas, star, pos);
    }
}

pub export fn projectConstellationGrids(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };

    if (canvas.settings.draw_constellation_grid or canvas.settings.draw_asterisms) {
        for (constellations) |constellation| {
            if (canvas.settings.zodiac_only and !constellation.is_zodiac) continue;
            
            if (canvas.settings.draw_constellation_grid) {
                star_math.projectConstellationGrid(&canvas, constellation, Pixel.rgba(255, 245, 194, 155), 1, pos);
            }
            if (canvas.settings.draw_asterisms) {
                star_math.projectConstellationAsterism(&canvas, constellation, Pixel.rgba(255, 245, 194, 155), 1, pos);
            }
        }
    }
}

pub export fn getConstellationAtPoint(x: f32, y: f32, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) isize {
    const point = Point{ .x = x, .y = y };

    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const index = star_math.getConstellationAtPoint(&canvas, point, constellations, pos);
    if (index) |i| {
        if (canvas.settings.draw_constellation_grid) {
            star_math.projectConstellationGrid(&canvas, constellations[i], Pixel.rgb(255, 255, 255), 2, pos);
        }
        if (canvas.settings.draw_asterisms) {
            star_math.projectConstellationAsterism(&canvas, constellations[i], Pixel.rgb(255, 255, 255), 2, pos);
        }
        return @intCast(isize, i);
    } else return -1;
}

pub export fn initializeResultData() [*]u8 {
    result_data = allocator.alloc(u8, 8) catch unreachable;
    return result_data.ptr;
}

pub export fn dragAndMove(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) void {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y, canvas.settings.drag_speed);
    setResult(coord.latitude, coord.longitude);
}

pub export fn findWaypoints(start_lat: f32, start_long: f32, end_lat: f32, end_long: f32) [*]Coord {
    const start = Coord{ .latitude = start_lat, .longitude = start_long };
    const end = Coord{ .latitude = end_lat, .longitude = end_long };

    const great_circle = GreatCircle(num_waypoints).init(start, end);

    std.mem.copy(Coord, waypoints, great_circle.waypoints[0..]);

    return waypoints.ptr;
}

pub export fn getCoordForSkyCoord(right_ascension: f32, declination: f32, observer_timestamp: i64) void {
    const sky_coord = SkyCoord{ .right_ascension = right_ascension, .declination = declination };
    const coord = sky_coord.getCoord(observer_timestamp);
    setResult(coord.latitude, coord.longitude);
}

pub export fn getSkyCoordForCanvasPoint(x: f32, y: f32, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const point = Point{ .x = x, .y = y };
    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const sky_coord = canvas.pointToCoord(point, pos) orelse SkyCoord{};
    setResult(sky_coord.right_ascension, sky_coord.declination);
}

pub export fn getCoordForCanvasPoint(x: f32, y: f32, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const point = Point{ .x = x, .y = y };
    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const sky_coord = canvas.pointToCoord(point, pos) orelse SkyCoord{};
    setResult(sky_coord.right_ascension, sky_coord.declination);
}

pub export fn getConstellationCentroid(constellation_index: usize) void {
    const centroid = if (constellation_index > constellations.len) SkyCoord{} else constellations[constellation_index].centroid();
    setResult(centroid.right_ascension, centroid.declination);
}

fn setResult(a: f32, b: f32) void {
    std.mem.copy(u8, @ptrCast([*]u8, result_data)[0..4], std.mem.toBytes(a)[0..]);
    std.mem.copy(u8, @ptrCast([*]u8, result_data)[4..8], std.mem.toBytes(b)[0..]);
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
