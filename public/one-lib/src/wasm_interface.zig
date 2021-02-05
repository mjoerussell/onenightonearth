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
const ConstellationGrid = star_math.ConstellationGrid;
const SkyCoord = star_math.SkyCoord;
const Coord = star_math.Coord;

const allocator = std.heap.page_allocator;
var canvas: Canvas = undefined;
var stars: []Star = undefined;
var constellation_grids: []ConstellationGrid = undefined;

pub export fn initialize(star_data: [*]Star, star_len: u32, constellation_data: [*][*]SkyCoord, coord_lens: [*]u32, num_constellations: u32, settings: *Canvas.Settings) void {
    stars = star_data[0..star_len];

    constellation_grids = allocator.alloc(ConstellationGrid, num_constellations) catch unreachable;
    defer allocator.free(coord_lens[0..num_constellations]);
    for (constellation_grids) |*c, i| {
        c.* = ConstellationGrid{
            .boundaries = constellation_data[i][0..coord_lens[i]]
        };
    }

    canvas = Canvas.init(allocator, settings.*) catch |err| switch (err) {
        error.OutOfMemory => {
            const num_pixels = canvas.settings.width * canvas.settings.height;
            log(.Error, "Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
            unreachable;
        }
    };

}

pub export fn updateCanvasSettings(settings: *Canvas.Settings) void {
    canvas.settings = settings.*;
    allocator.destroy(settings);
}

pub export fn getImageData(size_in_bytes: *u32) [*]Pixel {
    size_in_bytes.* = @intCast(u32, canvas.data.len * @sizeOf(Pixel));
    return canvas.data.ptr;
}

pub export fn resetImageData() void {
    for (canvas.data) |*p, i| {
        p.* = Pixel{};
    }   
}

pub export fn projectStars(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    for (stars) |star| {
        star_math.projectStar(&canvas, star, current_coord, observer_timestamp, true);
    }

    // star_math.drawSkyGrid(&canvas, current_coord, observer_timestamp);
}

pub export fn projectConstellationGrids(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    for (constellation_grids) |constellation| {
        star_math.projectConstellationGrid(&canvas, constellation, Pixel.rgba(255, 245, 194, 105), 1, current_coord, observer_timestamp);
    }
}

pub export fn getConstellationAtPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) isize {
    const observer_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };
    defer allocator.destroy(point);
    const index = star_math.getConstellationAtPoint(&canvas, point.*, constellation_grids, observer_coord, observer_timestamp);
    if (index) |i| {
        star_math.projectConstellationGrid(&canvas, constellation_grids[i], Pixel.rgb(255, 255, 255), 2, observer_coord, observer_timestamp);
        return @intCast(isize, i);
    } else return -1;
}

pub export fn dragAndMove(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) *Coord {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn findWaypoints(f: *const Coord, t: *const Coord, num_waypoints: *u32) [*]Coord {
    defer allocator.destroy(f);
    defer allocator.destroy(t);

    const waypoints = star_math.findWaypoints(allocator, f.*, t.*);
    num_waypoints.* = @intCast(u32, waypoints.len);
    return waypoints.ptr;
}

pub export fn getCoordForSkyCoord(sky_coord: *SkyCoord, observer_timestamp: i64) *Coord {
    defer allocator.destroy(sky_coord);
    const coord = star_math.getCoordForSkyCoord(sky_coord.*, observer_timestamp);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn getSkyCoordForCanvasPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) ?*SkyCoord {
    defer allocator.destroy(point);
    const observer_location = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };
    const sky_coord = star_math.getSkyCoordForCanvasPoint(&canvas, point.*, observer_location, observer_timestamp);
    if (sky_coord) |sk| {
        const sky_coord_ptr = allocator.create(SkyCoord) catch unreachable;
        sky_coord_ptr.* = sk;
        return sky_coord_ptr;
    } else {
        return null;
    }
}

pub export fn getCoordForCanvasPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) ?*Coord {
    defer allocator.destroy(point);
    const observer_location = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };
    const sky_coord = star_math.getSkyCoordForCanvasPoint(&canvas, point.*, observer_location, observer_timestamp);
    if (sky_coord) |sk| {
        log(.Debug, "Got sky coord ({d:.2}, {d:.2})", .{sk.right_ascension, sk.declination});
        const coord = star_math.getCoordForSkyCoord(sk, observer_timestamp);
        log(.Debug, "Got coord ({d:.2}, {d:.2})", .{coord.latitude, coord.longitude});
        const coord_ptr = allocator.create(Coord) catch unreachable;
        coord_ptr.* = coord;
        return coord_ptr;
    } else {
        return null;
    }
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch |err| return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
