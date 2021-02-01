const std = @import("std");
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;
const star_math = @import("./star_math.zig");
const render = @import("./render.zig");
const Canvas = render.Canvas;
const Pixel = render.Pixel;
const Star = star_math.Star;
const Constellation = star_math.Constellation;
const SkyCoord = star_math.SkyCoord;
const Coord = star_math.Coord;

const allocator = std.heap.page_allocator;
var canvas: Canvas = undefined;
var stars: []Star = undefined;
var constellations: []Constellation = undefined;

pub extern fn drawPointWasm(x: f32, y: f32, brightness: f32) void;

pub extern fn drawLineWasm(x1: f32, y1: f32, x2: f32, y2: f32) void;

pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;

fn log(comptime message: []const u8, args: anytype) void {
    var buffer: [400]u8 = undefined;
    const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch |err| return;
    consoleLog(fmt_msg.ptr, @intCast(u32, fmt_msg.len));
}

pub export fn initialize(star_data: [*]Star, star_len: u32, constellation_data: [*][*]SkyCoord, coord_lens: [*]u32, num_constellations: u32, settings: *Canvas.Settings) void {
    stars = star_data[0..star_len];

    constellations = allocator.alloc(Constellation, num_constellations) catch unreachable;
    defer allocator.free(coord_lens[0..num_constellations]);
    for (constellations) |*c, i| {
        c.* = Constellation{
            .boundaries = constellation_data[i][0..coord_lens[i]]
        };
    }

    for (constellations[0].boundaries) |b, i| {
        log("{}: ({d:.3}, {d:.3})", .{i, b.right_ascension, b.declination});
    }

    // const num_stars = star_math.initStarData(star_data[0..star_len]);
    canvas = Canvas.init(allocator, settings.*) catch |err| switch (err) {
        error.OutOfMemory => {
            const num_pixels = canvas.settings.width * canvas.settings.height;
            log("[ERROR] Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
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

pub export fn projectStarsWasm(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    for (stars) |star| {
        star_math.projectStar(&canvas, star, current_coord, observer_timestamp, true);
    }
}

pub export fn projectConstellations(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    for (constellations) |constellation| {
        star_math.projectConstellation(&canvas, constellation, current_coord, observer_timestamp);
    }
}

pub export fn dragAndMoveWasm(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) *Coord {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn findWaypointsWasm(f: *const Coord, t: *const Coord, num_waypoints: *u32) [*]Coord {
    defer allocator.destroy(f);
    defer allocator.destroy(t);

    const waypoints = star_math.findWaypoints(allocator, f.*, t.*);
    num_waypoints.* = @intCast(u32, waypoints.len);
    return waypoints.ptr;
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch |err| return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
