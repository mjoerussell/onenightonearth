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

const allocator = std.heap.page_allocator;
var canvas: Canvas = undefined;
var stars: []Star = undefined;

var constellations: []Constellation = undefined;

const ExternCanvasSettings = packed struct {
    width: u32,
    height: u32,
    background_radius: f32,
    zoom_factor: f32,
    draw_north_up: u8,
    draw_constellation_grid: u8,
    draw_asterisms: u8,

    fn getCanvasSettings(self: ExternCanvasSettings) Canvas.Settings {
        return Canvas.Settings{
            .width = self.width,
            .height = self.height,
            .background_radius = self.background_radius,
            .zoom_factor = self.zoom_factor,
            .draw_north_up = self.draw_north_up == 1,
            .draw_constellation_grid = self.draw_constellation_grid == 1,
            .draw_asterisms = self.draw_asterisms == 1
        };
    }
};

pub export fn initializeStars(star_data: [*]Star, star_len: u32) void {
    stars = star_data[0..star_len];
}

pub export fn initializeCanvas(settings: *ExternCanvasSettings) void {
    canvas = Canvas.init(allocator, settings.getCanvasSettings()) catch |err| switch (err) {
        error.OutOfMemory => {
            const num_pixels = canvas.settings.width * canvas.settings.height;
            log(.Error, "Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
            unreachable;
        }
    };
}

pub export fn initializeConstellations(constellation_grid_data: [*][*]SkyCoord, constellation_asterism_data: [*][*]SkyCoord, grid_coord_lens: [*]u32, asterism_coord_lens: [*]u32, num_constellations: u32) void {
    constellations = allocator.alloc(Constellation, num_constellations) catch unreachable;

    defer allocator.free(grid_coord_lens[0..num_constellations]);
    defer allocator.free(asterism_coord_lens[0..num_constellations]);
    for (constellations) |*c, i| {
        c.* = Constellation{
            .asterism = constellation_asterism_data[i][0..asterism_coord_lens[i]],
            .boundaries = constellation_grid_data[i][0..grid_coord_lens[i]]
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

    if (canvas.settings.draw_constellation_grid or canvas.settings.draw_asterisms) {
        for (constellations) |constellation| {
            if (canvas.settings.draw_constellation_grid) {
                star_math.projectConstellationGrid(&canvas, constellation, Pixel.rgba(255, 245, 194, 105), 1, current_coord, observer_timestamp);
            }
            if (canvas.settings.draw_asterisms) {
                star_math.projectConstellationAsterism(&canvas, constellation, Pixel.rgba(255, 245, 194, 105), 1, current_coord, observer_timestamp);
            }
        }
    }
}

pub export fn getConstellationAtPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) isize {
    const observer_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };
    defer allocator.destroy(point);
    const index = star_math.getConstellationAtPoint(&canvas, point.*, constellations, observer_coord, observer_timestamp);
    if (index) |i| {
        if (canvas.settings.draw_constellation_grid) {
            star_math.projectConstellationGrid(&canvas, constellations[i], Pixel.rgb(255, 255, 255), 2, observer_coord, observer_timestamp);
        }
        if (canvas.settings.draw_asterisms) {
            star_math.projectConstellationAsterism(&canvas, constellations[i], Pixel.rgb(255, 255, 255), 2, observer_coord, observer_timestamp);
        }
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

pub export fn getConstellationCentroid(constellation_index: usize) ?*SkyCoord {
    if (constellation_index > constellations.len) return null;

    const coord_ptr = allocator.create(SkyCoord) catch unreachable;
    coord_ptr.* = star_math.getConstellationCentroid(constellations[constellation_index]);
    return coord_ptr;
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch |err| return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
