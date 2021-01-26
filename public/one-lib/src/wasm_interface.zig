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

// pub export fn setZoomFactor(new_val: f32) void {
//     log("Setting zoom_factor to {d:.2}", .{new_val});
//     star_math.global_canvas.zoom_factor = new_val;
// }

// pub export fn setDrawNorthUp(should_draw_up: u8) void {
//     log("Setting draw_north_up to {}", .{should_draw_up});
//     star_math.global_canvas.draw_north_up = should_draw_up == 1;
// }

// pub export fn initialize(star_data: [*]const u8, data_len: u32, settings: *star_math.CanvasSettings, result_canvas_size: *u32) ?[*]Pixel {
pub export fn initialize(star_data: [*]const u8, data_len: u32, settings: *star_math.CanvasSettings) void {
    const num_stars = star_math.initStarData(allocator, star_data[0..data_len]) catch |err| blk: {
        switch (err) {
            error.ParseDec => log("[ERROR] Could not parse declination", .{}),
            error.ParseMag => log("[ERROR] Could not parse magnitude", .{}),
            error.ParseRA => log("[ERROR] Could not parse right ascension", .{}),
            error.OutOfMemory => log("[ERROR] Ran out of memory during initialization", .{})
        }
        // return null;
        break :blk 0;
    };
    // log("Init: Background Radius = {d:.3}", .{settings.background_radius});
    star_math.initCanvasData(settings.*);
    // star_math.initCanvasData(allocator, settings.*) catch |err| {
    //     log("[ERROR] Error while initializing canvas data", .{});
    //     unreachable;
    // };
    // result_canvas_size.* = star_math.global_pixel_data.len * @sizeOf(Pixel);

    // log("Set canvas size to {} pixels", .{star_math.global_pixel_data.len});

    // return star_math.global_pixel_data.ptr;
}

pub export fn updateCanvasSettings(settings: *star_math.CanvasSettings) void {
    star_math.global_canvas = settings.*;
    allocator.destroy(settings);
}

pub export fn projectStarsWasm(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64, result_len: *u32) [*]CanvasPoint {
    // const num_pixels = star_math.global_canvas.width * star_math.global_canvas.height;
    
    // const center_x: f32 = @intToFloat(f32, star_math.global_canvas.width) / 2.0;
    // const center_y: f32 = @intToFloat(f32, star_math.global_canvas.height) / 2.0;

    // // A multiplier used to convert a coordinate between [-1, 1] to a coordinate on the actual canvas, taking into
    // // account the rendering modifiers that can change based on the user zooming in/out or the travelling moving across poles
    // const direction_modifier: f32 = if (star_math.global_canvas.draw_north_up) 1.0 else -1.0;
    // const translate_factor: f32 = direction_modifier * star_math.global_canvas.background_radius * star_math.global_canvas.zoom_factor;
    // var pixel_data = allocator.alloc(Pixel, num_pixels) catch |err| {
    //     log("[ERROR] Error allocating memory for {} pixels", .{num_pixels});
    //     result_len.* = 0;
    //     return null;
    // };
    // for (pixel_data) |*pixel| {
    //     pixel.* = Pixel{};
    // }
    // result_len.* = pixel_data.len * @sizeOf(Pixel);
    var rendered_points = std.ArrayList(CanvasPoint).initCapacity(allocator, star_math.global_stars.len / 2) catch unreachable;

    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    // for (star_math.global_stars) |star, i| {
    //     if (i > 10) break;
    //     log("Original Star {}: ({d:.3}, {d:.3})", .{i, star.right_ascension, star.declination});
    // }

    // log("Canvas width: {d:.2}, Canvas height: {d:.2}", .{star_math.global_canvas.width, star_math.global_canvas.height});
    // log("Background Radius: {d:.4}", .{star_math.global_canvas.background_radius});
    // log("Zoom Factor: {d:.4}", .{star_math.global_canvas.zoom_factor});
    // log("Draw North Up? {}", .{star_math.global_canvas.draw_north_up});

    // var num_stars: u32 = 0;
    for (star_math.global_stars) |star| {
        const point = star_math.projectStar(star, current_coord, observer_timestamp, true);
        if (point) |p| {
            rendered_points.append(p) catch unreachable;
            // if (num_stars > 100 and num_stars < 150) {
            //     log("Drawing star {} at ({d:.2}, {d:.2})", .{star.name, star.right_ascension, star.declination});
            // }
            // const x: f32 = center_x + (translate_factor * p.x);
            // const y: f32 = center_y - (translate_factor * p.y);

            // const pixel_index: i32 = @floatToInt(i32, x) + (@intCast(i32, star_math.global_canvas.width) * @floatToInt(i32, y));
            // if (pixel_index < 0 or pixel_index >= star_math.global_pixel_data.len) {
            //     continue;
            // }

            // const alpha: u8 = blk: {
            //     const raw_alpha: f32 = (p.brightness / 1.5) * 255.0;
            //     if (raw_alpha <= 0.0) break :blk 0;
            //     if (raw_alpha >= 255.0) break :blk 255;

            //     break :blk @floatToInt(u8, raw_alpha);
            // };
            
            // const pixel = Pixel{
            //     .r = 255,
            //     .g = 246, 
            //     .b = 176,
            //     .a = alpha
            // };

            // star_math.global_pixel_data[@intCast(usize, pixel_index)] = pixel;
            // num_stars += 1;
        }
    }   

    const result = rendered_points.toOwnedSlice();

    // for (result[0..10]) |star, i| {
    //     log("Star {}: ({d:.3}, {d:.3})", .{i, star.x, star.y});
    // }

    result_len.* = @intCast(u32, result.len);
    return result.ptr;
    // return pixel_data.ptr;
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
