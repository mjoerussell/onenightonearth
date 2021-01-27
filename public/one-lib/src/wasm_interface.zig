const std = @import("std");
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;
const star_math = @import("./star_math.zig");
const Star = star_math.Star;
const StarCoord = star_math.StarCoord;
const ConstellationBranch = star_math.ConstellationBranch;
const Coord = star_math.Coord;
const CanvasPoint = star_math.CanvasPoint;
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

pub export fn initialize(star_data: [*]const u8, data_len: u32, settings: *star_math.CanvasSettings) void {
    const num_stars = star_math.initStarData(allocator, star_data[0..data_len]) catch |err| blk: {
        switch (err) {
            error.ParseDec => log("[ERROR] Could not parse declination", .{}),
            error.ParseMag => log("[ERROR] Could not parse magnitude", .{}),
            error.ParseRA => log("[ERROR] Could not parse right ascension", .{}),
            error.OutOfMemory => log("[ERROR] Ran out of memory during initialization", .{})
        }
        break :blk 0;
    };
    star_math.initCanvasData(allocator, settings.*) catch unreachable;
    log("Initialized {} pixels", .{star_math.global_pixel_data.len});

}

pub export fn updateCanvasSettings(settings: *star_math.CanvasSettings) void {
    star_math.global_canvas = settings.*;
    allocator.destroy(settings);
}

pub export fn getImageData(size_in_bytes: *u32) [*]Pixel {
    size_in_bytes.* = @intCast(u32, star_math.global_pixel_data.len * @sizeOf(star_math.Pixel));
    return star_math.global_pixel_data.ptr;
}

// pub export fn projectStarsWasm(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64, result_len: *u32) [*]CanvasPoint {
pub export fn projectStarsWasm(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    // var rendered_points = std.ArrayList(CanvasPoint).initCapacity(allocator, star_math.global_stars.len / 2) catch unreachable;

    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    for (star_math.global_pixel_data) |*p| {
        p.* = Pixel{};
    }

    log("Reset pixel data", .{});

    for (star_math.global_stars) |star, i| {
        const point = star_math.projectStar(star, current_coord, observer_timestamp, true);
        if (point) |p| {
            if (std.math.isNan(p.x) or std.math.isNan(p.y) or std.math.isNan(p.brightness)) {
                log("Point for star {} has NaN value", .{i});
                continue;
            }
            const p_index: i32 = @floatToInt(i32, (p.y * @intToFloat(f32, star_math.global_canvas.width)) + p.x);
            if (p_index < 0 or p_index >= star_math.global_pixel_data.len) {
                continue;
            }
            // log("{}: Drawing star at {}", .{i, p_index});
            star_math.global_pixel_data[@intCast(usize, p_index)] = Pixel{
                .r = 255, 
                .g = 246, 
                .b = 176, 
                .a = @floatToInt(u8, (p.brightness / 2.5) * 255.0)
            };
            // log("{}: Drew star at pixel {}", .{i, p_index});
            // drawPointWasm(p.x, p.y, p.brightness);
            // rendered_points.append(p) catch unreachable;
        }
    }   

    log("Drew all stars", .{});

    // const result = rendered_points.toOwnedSlice();
    // const points = star_math.projectStars(allocator, current_coord, observer_timestamp, true) catch unreachable;
    // log("Drawing {} points", .{points.len});
    // for (points) |p| {
    //     drawPointWasm(p.x, p.y, p.brightness);
    // }
    // result_len.* = @intCast(u32, result.len);
    // return result.ptr;
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
