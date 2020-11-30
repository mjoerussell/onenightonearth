const std = @import("std");
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;
const star_math = @import("./star_math.zig");
const Star = star_math.Star;
const StarIterator = star_math.StarIterator;
const StarCoord = star_math.StarCoord;
const ConstellationBranch = star_math.ConstellationBranch;
const Coord = star_math.Coord;
const CanvasPoint = star_math.CanvasPoint;

const allocator = std.heap.page_allocator;

pub extern fn drawPointWasm(x: f32, y: f32, brightness: f32) void;

pub extern fn drawLineWasm(x1: f32, y1: f32, x2: f32, y2: f32) void;

pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;

fn log(comptime message: []const u8, args: anytype) void {
    var buffer: [400]u8 = undefined;
    const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch |err| return;
    consoleLog(fmt_msg.ptr, @intCast(u32, fmt_msg.len));
}

pub export fn initialize(star_data: [*]const u8, data_len: u32) void {
    star_math.initData(allocator, star_data[0..data_len]) catch unreachable;
}

pub export fn projectStarsWasm(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64, result_len: *u32) ?[*]CanvasPoint {
    var points = allocator.alloc(CanvasPoint, star_math.global_stars.len) catch |err| return null;
    var num_points: u32 = 0;
    for (star_math.global_stars) |star, index| {
        const point = star_math.projectStar(star, .{ .latitude = observer_latitude, .longitude = observer_longitude}, observer_timestamp, true);
        if (point) |p| {
            points[num_points] = p;
            num_points += 1;
        }
    }

    result_len.* = num_points;
    const final_points = allocator.realloc(points, num_points) catch |err| return null;
    return final_points.ptr;
}

// pub export fn projectConstellation(branches: [*]const ConstellationBranch, num_branches: u32, observer_location: *const Coord, observer_timestamp: i64) void {
//     // Allocate for now, bail if not possible
//     const branch_ends = allocator.alloc(StarCoord, num_branches * 2) catch |err| return;
//     var index: usize = 0;
//     for (branches[0..num_branches]) |branch| {
//         branch_ends[index] = branch.a;
//         branch_ends[index + 1] = branch.b;
//         index += 2;
//     }
//     defer allocator.free(branches[0..num_branches]);
//     // @todo Keep locatation across multiple branches 
//     defer allocator.destroy(observer_location);

//     const projected_points = star_math.projectStars(allocator, StarCoord, branch_ends, observer_location.*, observer_timestamp, false);


//     if (projected_points) |points| {
//         defer allocator.free(points);
//         var point_index: usize = 0;
//         while (point_index < points.len) : (point_index += 2) {
//             drawLineWasm(points[point_index].x, points[point_index].y, points[point_index + 1].x, points[point_index + 1].y);
//         }
//     } else |_| {}

// }

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

pub export fn getProjectedCoordWasm(altitude: f32, azimuth: f32, brightness: f32) ?*CanvasPoint {
    var point = star_math.getProjectedCoord(altitude, azimuth);
    point.brightness = brightness;
    const ptr = allocator.create(CanvasPoint) catch |err| {
        return null;
    };
    ptr.* = point;
    return ptr;
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch |err| return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);
}
