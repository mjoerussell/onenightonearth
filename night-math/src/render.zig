const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const log = @import("./log.zig").log;
const math_utils = @import("./math_utils.zig");
const Point = math_utils.Point;
const Line = math_utils.Line;

const star_math = @import("./star_math.zig");
const SkyCoord = star_math.SkyCoord;
const Star = star_math.Star;
const ObserverPosition = star_math.ObserverPosition;

pub const Pixel = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub fn rgb(r: u8, g: u8, b: u8) Pixel {
        return Pixel{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Pixel {
        return Pixel{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn asU32(pixel: Pixel) u32 {
        return @ptrCast(*const u32, @alignCast(4, &pixel)).*;
    }

    pub fn fromU32(value: u32) Pixel {
        return @ptrCast(*align(4) const Pixel, &value).*;
    }

};

pub const Canvas = struct {
    pub const Settings = struct {
        width: u32,
        height: u32,
        background_radius: f32,
        zoom_factor: f32,
        drag_speed: f32,
        draw_north_up: bool,
        draw_constellation_grid: bool,
        draw_asterisms: bool,
        zodiac_only: bool,
    };

    data: []u32,
    pixel_mask: []const u32,
    settings: Settings,

    pub fn init(allocator: Allocator, settings: Settings) !Canvas {
        var canvas: Canvas = undefined;
        canvas.settings = settings;
        const num_pixels = canvas.settings.width * canvas.settings.height;
        canvas.data = try allocator.alloc(u32, num_pixels);
        for (canvas.data) |*p| {
            p.* = 0;
        }

        var pixel_mask = try allocator.alloc(u32, num_pixels);
        // canvas.pixel_mask = try allocator.alloc(Pixel, canvas.settings.width * canvas.settings.height);
        // canvas.pixel_mask.ensureTotalCapacity(allocator, num_pixels);
        for (pixel_mask) |*p, p_index| {
            const x = @intToFloat(f32, p_index % canvas.settings.width);
            const y = @intToFloat(f32, @divFloor(p_index, canvas.settings.width));
            const mask_value = 
                if (canvas.isInsideCircle(.{ .x = x, .y = y })) Pixel.rgba(255, 255, 255, 255)
                else Pixel.rgba(0, 0, 0, 0);
            p.* = mask_value.asU32();
        }

        canvas.pixel_mask = pixel_mask;
        return canvas;
    }

    pub fn resetImageData(canvas: *Canvas) void {
        @memset(@ptrCast([*]u8, canvas.data.ptr), 0, canvas.data.len * @sizeOf(u32));
    }

    // pub fn setPixelAtWide(self: *Canvas, points: std.MultiArrayList(Point), pixels: []Pixel) void {
    //     const u32x4 = @Vector(4, u32);
        
    //     const points_slice = points.slice();
    //     const xs = points_slice.items(.x);
    //     const ys = points_slice.items(.y);

    //     var point_index: usize = 0;
    //     while (point_index < xs.len) : (point_index += 4) {
    //         const x_x4: u32x4 = .{ @floatToInt(u32, xs[point_index]), @floatToInt(u32, xs[point_index + 1]), @floatToInt(u32, xs[point_index + 2]), @floatToInt(u32, xs[point_index + 3]) };
    //     }
    // }

    pub fn setPixelAt(canvas: *Canvas, point: Point, new_pixel: Pixel) void {
        if (std.math.isNan(point.x) or std.math.isNan(point.y)) {
            return;
        }

        if (point.x < 0 or point.y < 0) return;
        if (point.x > @intToFloat(f32, canvas.settings.width) or point.y > @intToFloat(f32, canvas.settings.height)) return;

        const x = @floatToInt(usize, point.x);
        const y = @floatToInt(usize, point.y);

        const p_index: usize = (y * @intCast(usize, canvas.settings.width)) + x;
        if (p_index >= canvas.data.len) return;

        canvas.data[p_index] = canvas.pixel_mask[p_index] & new_pixel.asU32();
    }

    pub fn coordToPointWide(canvas: Canvas, sky_coords: std.MultiArrayList(Star), local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32, points: *std.MultiArrayList(Point)) void {
        const f32x4 = @Vector(4, f32);
        
        // Constants for calculating sky coord-to-point
        const radius_x4 = @splat(4, @as(f32, 2 / math.pi)); 
        const lst_x4 = @splat(4, local_sidereal_time);
        const sin_lat_x4 = @splat(4, sin_latitude);
        const cos_lat_x4 = @splat(4, cos_latitude);

        // Constants for translatePoint
        const center_x = @splat(4, @intToFloat(f32, canvas.settings.width) / 2);
        const center_y = @splat(4, @intToFloat(f32, canvas.settings.height) / 2);
        const direction_modifier: f32x4 = if (canvas.settings.draw_north_up) @splat(4, @as(f32, 1)) else @splat(4, @as(f32, -1));
        const translate_factor = direction_modifier * @splat(4, canvas.settings.background_radius) * @splat(4, canvas.settings.zoom_factor);

        const coord_slice = sky_coords.slice();
        const point_slice = points.slice();
        const right_ascensions = coord_slice.items(.right_ascension);

        const sin_decs = coord_slice.items(.sin_declination);
        const cos_decs = coord_slice.items(.cos_declination);

        var points_x = point_slice.items(.x);
        var points_y = point_slice.items(.y);

        var index: usize = 0;
        while (index < right_ascensions.len) : (index += 4) {
            const ra_x4: f32x4 = [_]f32{ right_ascensions[index], right_ascensions[index + 1], right_ascensions[index + 2], right_ascensions[index + 3] };
            const sin_dec_x4: f32x4 = [_]f32{ sin_decs[index], sin_decs[index + 1], sin_decs[index + 2], sin_decs[index + 3] };
            const cos_dec_x4: f32x4 = [_]f32{ cos_decs[index], cos_decs[index + 1], cos_decs[index + 2], cos_decs[index + 3] };

            const hour_angle = lst_x4 - ra_x4;
            const sin_alt = sin_dec_x4 * sin_lat_x4 + cos_dec_x4 * cos_lat_x4 * @cos(hour_angle);
            const altitude: f32x4 = [_]f32{ math.asin(sin_alt[0]), math.asin(sin_alt[1]), math.asin(sin_alt[2]), math.asin(sin_alt[3]), };

            const cos_azi = (sin_dec_x4 - sin_alt * sin_lat_x4) / (@cos(altitude) * cos_lat_x4);
            const azi: f32x4 = [_]f32{ math.acos(cos_azi[0]), math.acos(cos_azi[1]), math.acos(cos_azi[2]), math.acos(cos_azi[3]), };
            const pred = @sin(hour_angle) < @splat(4, @as(f32, 0));
            // If the sin(hour_angle) is less than zero (pred), then use -azimuth instead of the regular calculated azimuth
            const azimuth = @select(f32, pred, -azi, azi);
            
            const s = @splat(4, @as(f32, 1)) - (radius_x4 * altitude);
        
            const x_x4 = s * @sin(azimuth);
            const y_x4 = s * cos_azi;

            const translate_x = center_x + (translate_factor * x_x4);
            const translate_y = center_y - (translate_factor * y_x4);

            points_x[index] = translate_x[0];
            points_x[index + 1] = translate_x[1];
            points_x[index + 2] = translate_x[2];
            points_x[index + 3] = translate_x[3];

            points_y[index] = translate_y[0];
            points_y[index + 1] = translate_y[1];
            points_y[index + 2] = translate_y[2];
            points_y[index + 3] = translate_y[3];

            // const x_u32x4 = .{ 
            //     @floatToInt(u32, translate_x[0]), 
            //     @floatToInt(u32, translate_x[1]), 
            //     @floatToInt(u32, translate_x[2]), 
            //     @floatToInt(u32, translate_x[3]),
            // };

            // const y_u32x4 = .{ 
            //     @floatToInt(u32, translate_y[0]), 
            //     @floatToInt(u32, translate_y[1]), 
            //     @floatToInt(u32, translate_y[2]), 
            //     @floatToInt(u32, translate_y[3]),
            // };

            // const p_index_x4 = (y_u32x4 * @splat(4, canvas.settings.width)) + x_u32x4;




            // if (std.math.isNan(point.x) or std.math.isNan(point.y)) {
            //     return;
            // }



            // if (point.x < 0 or point.y < 0) return;
            // if (point.x > @intToFloat(f32, self.settings.width) or point.y > @intToFloat(f32, self.settings.height)) return;

            // const x = @floatToInt(usize, point.x);
            // const y = @floatToInt(usize, point.y);

            // const p_index: usize = (y * @intCast(usize, self.settings.width)) + x;
            // if (p_index >= self.data.len) return;

            // self.data[p_index].r = self.pixel_mask[p_index].r & new_pixel.r;
            // self.data[p_index].g = self.pixel_mask[p_index].g & new_pixel.g;
            // self.data[p_index].b = self.pixel_mask[p_index].b & new_pixel.b;
            // self.data[p_index].a = self.pixel_mask[p_index].a & new_pixel.a;
        }
    }

    pub fn coordToPoint(canvas: Canvas, sky_coord: SkyCoord, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32, filter_below_horizon: bool) ?Point {
        const two_pi = comptime math.pi * 2.0;

        const hour_angle = local_sidereal_time - sky_coord.right_ascension;
        const sin_dec = math.sin(sky_coord.declination);
        
        const sin_alt = sin_dec * sin_latitude + math.cos(sky_coord.declination) * cos_latitude * math.cos(hour_angle);
        const altitude = math.asin(sin_alt);
        if (filter_below_horizon and altitude < 0) {
            return null;
        }

        const cos_azi = (sin_dec - sin_alt * sin_latitude) / (math.cos(altitude) * cos_latitude);
        const azi = math.acos(cos_azi);
        const azimuth = if (math.sin(hour_angle) < 0) azi else two_pi - azi;

        const canvas_point = blk: {
            const radius = comptime 2.0 / math.pi;
            // s is the distance from the center of the projection circle to the point
            // aka 1 - the angular distance along the surface of the sky sphere
            const s = 1.0 - (radius * altitude);

            // Convert from polar to cartesian coordinates
            break :blk Point{ 
                // @note without negating x here, the whole chart is rendered backwards. Not sure if this is where the negations
                // is SUPPOSED to go, or if I messed up a negation somewhere else and this is just a hack that makes it work
                .x = -s * math.sin(azimuth), 
                .y = s * cos_azi
            };
        };

        return canvas.translatePoint(canvas_point);
    }

    pub fn translatePoint(self: Canvas, pt: Point) Point {
        const center = Point{
            .x = @intToFloat(f32, self.settings.width) / 2.0,
            .y = @intToFloat(f32, self.settings.height) / 2.0,
        };

        // A multiplier used to convert a coordinate between [-1, 1] to a coordinate on the actual canvas, taking into
        // account the rendering modifiers that can change based on the user zooming in/out or the travelling moving across poles
        const direction_modifier: f32 = if (self.settings.draw_north_up) 1.0 else -1.0;
        const translate_factor: f32 = direction_modifier * self.settings.background_radius * self.settings.zoom_factor;

        return Point{
            .x = center.x + (translate_factor * pt.x),
            .y = center.y - (translate_factor * pt.y)
        };
    }

    pub fn isInsideCircle(self: Canvas, point: Point) bool {
        const center = Point{
            .x = @intToFloat(f32, self.settings.width) / 2.0,
            .y = @intToFloat(f32, self.settings.height) / 2.0,
        };

        return point.getDist(center) <= self.settings.background_radius;
    }

    pub fn drawLine(self: *Canvas, line: Line, color: Pixel) void {
        if (math.isNan(line.a.x) or math.isNan(line.a.y) or math.isNan(line.b.x) or math.isNan(line.b.y)) return;

        const IntPoint = struct {
            x: i32,
            y: i32,

            fn toPoint(int_point: @This()) Point {
                return .{ .x = @intToFloat(f32, int_point.x), .y = @intToFloat(f32, int_point.y) };
            }
        };

        var a = IntPoint{ .x = @floatToInt(i32, line.a.x), .y = @floatToInt(i32, line.a.y) };
        var b = IntPoint{ .x = @floatToInt(i32, line.b.x), .y = @floatToInt(i32, line.b.y) };

        const dist_x = math.absInt(b.x - a.x) catch unreachable;
        const dist_y = -(math.absInt(b.y - a.y) catch unreachable);

        const step_x: i32 = if (a.x < b.x) 1 else -1;
        const step_y: i32 = if (a.y < b.y) 1 else -1;

        var curr_point = a;
        var err = dist_x + dist_y;
        while (true) {
            var f_point = curr_point.toPoint();
            self.setPixelAt(f_point, color);
            // if (self.isInsideCircle(f_point)) self.setPixelAt(f_point, color);

            if (curr_point.x == b.x and curr_point.y == b.y) break;

            const err_2 = 2 * err;
            if (err_2 >= dist_y) {
                err += dist_y;
                curr_point.x += step_x;
            }
            if (err_2 <= dist_x) {
                err += dist_x;
                curr_point.y += step_y;
            }
        }
    }
};

test "coord to point conversion" {
    const canvas_settings = Canvas.Settings{
        .width = 700,
        .height = 700,
        .draw_north_up = true,
        .background_radius = 0.45 * 700.0,
        .zoom_factor = 1.0,
        .draw_asterisms = false,
        .draw_constellation_grid = false,
        .drag_speed = 0,
        .zodiac_only = false,
    };

    var canvas = try Canvas.init(std.testing.allocator, canvas_settings);
    defer std.testing.allocator.free(canvas.data);

    const original_sky_coord = SkyCoord{
        .right_ascension = 125.07948333 * (math.pi / 180.0),
        .declination = -87.72806111 * (math.pi / 180.0),
    };

    const original_coord = ObserverPosition{
        .latitude = 56.5 * (math.pi / 180.0),
        .longitude = -127.23 * (math.pi / 180.0),
        .timestamp = 1635524865511,
    };

    const coord_to_point = canvas.coordToPoint(original_sky_coord, original_coord.localSiderealTime(), math.sin(original_coord.latitude), math.cos(original_coord.latitude), false).?;
    const point_to_coord = canvas.pointToCoord(coord_to_point, original_coord).?;

    try std.testing.expectEqual(original_sky_coord, point_to_coord);

}