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
// var allocator_buffer: [1024]u8 = undefined;
// var allocator: std.mem.Allocator = std.heap.page_allocator;

var canvas: Canvas = undefined;
var stars: []Star = undefined;
var waypoints: []Coord = undefined;
const num_waypoints = 150;

var constellations: []Constellation = undefined;

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

pub export fn initializeAllocator() void {
    // var fba = std.heap.FixedBufferAllocator.init(allocator_buffer[0..]);
    // allocator = fba.allocator;
}

pub export fn initializeStars(star_data: [*]Star, star_len: u32) void {
    stars = star_data[0..star_len];
    waypoints = allocator.alloc(Coord, num_waypoints) catch unreachable;
}

pub export fn initializeCanvas(settings: *ExternCanvasSettings) void {
    // canvas = Canvas.init(&allocator, settings.getCanvasSettings()) catch |err| switch (err) {
    canvas = Canvas.init(allocator, settings.getCanvasSettings()) catch |err| switch (err) {
        error.OutOfMemory => {
            const num_pixels = canvas.settings.width * canvas.settings.height;
            log(.Error, "Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
            unreachable;
        }
    };
}

pub export fn initializeConstellations(constellation_grid_data: [*][*]SkyCoord, constellation_asterism_data: [*][*]SkyCoord, constellation_zodiac_data: [*]u8, grid_coord_lens: [*]u32, asterism_coord_lens: [*]u32, num_constellations: u32) void {
    constellations = allocator.alloc(Constellation, num_constellations) catch unreachable;

    defer allocator.free(grid_coord_lens[0..num_constellations]);
    defer allocator.free(asterism_coord_lens[0..num_constellations]);
    for (constellations) |*c, i| {
        c.* = Constellation{
            .asterism = constellation_asterism_data[i][0..asterism_coord_lens[i]],
            .boundaries = constellation_grid_data[i][0..grid_coord_lens[i]],
            .is_zodiac = constellation_zodiac_data[i] == 1,
        };
    }

}

pub export fn updateCanvasSettings(settings: *ExternCanvasSettings) void {
    canvas.settings = settings.getCanvasSettings();
    allocator.destroy(settings);
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

pub export fn getConstellationAtPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) isize {
    defer allocator.destroy(point);

    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const index = star_math.getConstellationAtPoint(&canvas, point.*, constellations, pos);
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

pub export fn dragAndMove(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) *Coord {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y, canvas.settings.drag_speed);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn findWaypoints(start_lat: f32, start_long: f32, end_lat: f32, end_long: f32) [*]Coord {
    const start = Coord{ .latitude = start_lat, .longitude = start_long };
    const end = Coord{ .latitude = end_lat, .longitude = end_long };

    const great_circle = GreatCircle(num_waypoints).init(start, end);

    std.mem.copy(Coord, waypoints, great_circle.waypoints[0..]);

    return waypoints.ptr;
}

pub export fn getCoordForSkyCoord(sky_coord: *SkyCoord, observer_timestamp: i64) *Coord {
    defer allocator.destroy(sky_coord);
    const coord = sky_coord.getCoord(observer_timestamp);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn getSkyCoordForCanvasPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) ?*SkyCoord {
    defer allocator.destroy(point);

    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const sky_coord = canvas.pointToCoord(point.*, pos) orelse return null;
    const sky_coord_ptr = allocator.create(SkyCoord) catch unreachable;
    sky_coord_ptr.* = sky_coord;
    return sky_coord_ptr;
}

pub export fn getCoordForCanvasPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) ?*Coord {
    defer allocator.destroy(point);

    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const sky_coord = canvas.pointToCoord(point.*, pos) orelse return null;
    const coord = sky_coord.getCoord(observer_timestamp);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn getConstellationCentroid(constellation_index: usize) ?*SkyCoord {
    if (constellation_index > constellations.len) return null;

    const coord_ptr = allocator.create(SkyCoord) catch unreachable;
    coord_ptr.* = constellations[constellation_index].centroid();
    return coord_ptr;
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
