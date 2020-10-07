const std = @import("std");
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;
const star_math = @import("./star_math.zig");
const job_queue = @import("./job_queue.zig");
const Star = star_math.Star;
const Coord = star_math.Coord;
const CanvasPoint = star_math.CanvasPoint;

/// Type alias for a pointer that has been converted to int via @ptrToInt
const ext_pointer = usize;
const allocator = std.heap.page_allocator;

fn getRightAscension(star_entry: []const u8) f32 {
    const ra_hours = if (parseFloat(f32, star_entry[75..77])) |f| f else |_| 0;
    const ra_mins = if (parseFloat(f32, star_entry[77..79])) |f| f else |_| 0;
    const ra_secs = if (parseFloat(f32, star_entry[79..83])) |f| f else |_| 0;

    const total_ra_hours = ra_hours + (ra_mins + ra_secs / 60.0) / 60.0;

    return total_ra_hours * 15.0;
}

fn getDeclination(star_entry: []const u8) f32 {
    const dec_sign = star_entry[83..84];
    const dec_degrees = if (parseFloat(f32, star_entry[84..86])) |f| f else |_| 0;
    const dec_arc_minutes = if (parseFloat(f32, star_entry[86..88])) |f| f else |_| 0;
    const dec_arc_seconds = if (parseFloat(f32, star_entry[88..90])) |f| f else |_| 0;

    const total_dec_arc_minutes = dec_arc_minutes + dec_arc_seconds / 60.0;
    const total_dec_degrees = dec_degrees + total_dec_arc_minutes / 60.0;

    if (dec_sign == "-") {
        return -total_dec_degrees;
    }

    return total_dec_degrees;
}

fn getMagnitude(star_entry: []const u8) f32 {
    var magnitude: f32 = if (parseFloat(f32, star_entry[103..107])) |f| f else |_| 0;
    magnitude -= 8.0;
    magnitude = magnitude / -12.0;

    return magnitude;
}

const catalog = @embedFile("catalog");

// @warn Does not work on WASM so the compilation will fail if you try to use it
fn getStars(alloc: *std.mem.Allocator) ![]Star {
    const Job = struct {
        fn run(line: []const u8) Star {
            return .{
                .right_ascension = getRightAscension(line),
                .declination = getDeclination(line),
                .brightness = getMagnitude(line),
            };
        }
    };

    var lines = job_queue.LineIterator.create(catalog);
    // var stars: []Star = try alloc.alloc(Star, 10000);
    var jq = try job_queue.JobQueue([]const u8, Star, 4).init(allocator, 10_000, Job.run);
    var index: usize = 0;

    while (lines.next_line()) |line| : (index += 1) {
        if (std.mem.eql(u8, line, "")) continue;
        const next_star: Star = .{
            .right_ascension = getRightAscension(line),
            .declination = getDeclination(line),
            .brightness = getMagnitude(line),
        };

        if (next_star.right_ascension == 0.0 or next_star.declination == 0.0) continue;
        try jq.enqueue_job_input(line);
    }

    return jq.finish_jobs();
}

pub extern fn drawPointWasm(x: f32, y: f32, brightness: f32) void;

pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;

fn log(comptime message: []const u8, args: anytype) void {
    var buffer: [400]u8 = undefined;
    const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch |err| return;
    consoleLog(fmt_msg.ptr, @intCast(u32, fmt_msg.len));
}

pub export fn projectStarsWasm(ab_stars: [*]const Star, num_stars: u32, observer_location: *const Coord, observer_timestamp: i64) void {
    const bounded_stars = ab_stars[0..num_stars];
    defer allocator.free(bounded_stars);
    defer allocator.destroy(observer_location);

    const projected_points = star_math.projectStars(allocator, bounded_stars, observer_location.*, observer_timestamp);

    if (projected_points) |points| {
        defer allocator.free(points);
        for (points) |point| {
            drawPointWasm(point.x, point.y, point.brightness);
        }
    } else |_| {}
}

pub export fn dragAndMoveWasm(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) *Coord {
    const coord = star_math.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
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
