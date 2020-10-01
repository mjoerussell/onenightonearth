const std = @import("std");
const star_math = @import("./star_math.zig");
const Star = star_math.Star;
const Coord = star_math.Coord;
const CanvasPoint = star_math.CanvasPoint;

/// Type alias for a pointer that has been converted to int via @ptrToInt
const ext_pointer = usize;
const allocator = std.heap.page_allocator;

pub extern fn drawPointWasm(x: f32, y: f32, brightness: f32) void;

// pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;

// fn log(comptime message: []const u8, args: anytype) void {
//     var buffer: [200]u8 = undefined;
//     const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch |err| return;
//     consoleLog(fmt_msg.ptr, @intCast(u32, fmt_msg.len));
// }

pub export fn projectStarsWasm(stars: [*]const Star, num_stars: u32, observer_location: *const Coord, observer_timestamp: i64) void {
    const bounded_stars = stars[0..num_stars];
    defer allocator.free(bounded_stars);
    defer allocator.destroy(observer_location);

    const projected_points = star_math.projectStars(allocator, bounded_stars, observer_location.*, observer_timestamp);

    if (projected_points) |points| {
        for (points) |point| {
            drawPointWasm(point.x, point.y, point.brightness);
        }
    } else |_| {}
}

pub export fn findWaypointsWasm(f: *const Coord, t: *const Coord, num_waypoints: u32) ext_pointer {
    defer allocator.destroy(f);
    defer allocator.destroy(t);

    const waypoints = star_math.findWaypoints(allocator, f.*, t.*, num_waypoints);
    return @ptrToInt(waypoints.ptr);
}

pub export fn getProjectedCoordWasm(altitude: f32, azimuth: f32, brightness: f32) ext_pointer {
    const point = star_math.getProjectedCoord(altitude, azimuth, brightness);
    const ptr = allocator.create(CanvasPoint) catch |err| {
        return 0;
    };
    ptr.* = point;
    return @ptrToInt(ptr);
}

pub export fn _wasm_alloc(byte_len: u32) ext_pointer {
    const buffer = allocator.alloc(u8, byte_len) catch |err| return 0;
    return @ptrToInt(buffer.ptr);
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
