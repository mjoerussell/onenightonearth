const std = @import("std");
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;
const star_math = @import("./star_math.zig");
const Star = star_math.Star;
const Coord = star_math.Coord;
const Pixel = star_math.Pixel;

const allocator = std.heap.page_allocator;

pub extern fn drawPointWasm(x: f32, y: f32, brightness: f32) void;

pub extern fn drawLineWasm(x1: f32, y1: f32, x2: f32, y2: f32) void;

pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;

fn log(comptime message: []const u8, args: anytype) void {
    var buffer: [400]u8 = undefined;
    const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch |err| return;
    consoleLog(fmt_msg.ptr, @intCast(u32, fmt_msg.len));
}

pub export fn initialize(star_data: [*]Star, data_len: u32, settings: *star_math.CanvasSettings) void {
    const num_stars = star_math.initStarData(allocator, star_data[0..data_len]) catch |err| blk: {
        switch (err) {
            error.OutOfMemory => log("[ERROR] Ran out of memory during initialization (needed {} kB for {} stars)", .{(data_len * @sizeOf(Star)) / 1000, data_len})
        }
        break :blk 0;
    };
    star_math.initCanvasData(allocator, settings.*) catch |err| switch (err) {
        error.OutOfMemory => {
            const num_pixels = star_math.global_canvas.width * star_math.global_canvas.height;
            log("[ERROR] Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
            unreachable;
        }
    };
}

pub export fn updateCanvasSettings(settings: *star_math.CanvasSettings) void {
    star_math.global_canvas = settings.*;
    allocator.destroy(settings);
}

pub export fn getImageData(size_in_bytes: *u32) [*]Pixel {
    size_in_bytes.* = @intCast(u32, star_math.global_pixel_data.len * @sizeOf(star_math.Pixel));
    return star_math.global_pixel_data.ptr;
}

pub export fn resetImageData() void {
    for (star_math.global_pixel_data) |*p, i| {
        p.* = Pixel{};
    }   
}

pub export fn projectStarsWasm(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    star_math.projectStar(current_coord, observer_timestamp, true);
}

pub export fn dragAndMoveWasm(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) *Coord {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn findWaypointsWasm(f: *const Coord, t: *const Coord, num_waypoints: u32) [*]Coord {
    defer allocator.destroy(f);
    defer allocator.destroy(t);

    const waypoints = star_math.findWaypoints(allocator, f.*, t.*, num_waypoints);
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
