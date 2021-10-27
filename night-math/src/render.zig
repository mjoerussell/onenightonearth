const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const log = @import("./log.zig").log;
const math_utils = @import("./math_utils.zig");
const Point = math_utils.Point;
const Line = math_utils.Line;

const star_math = @import("./star_math.zig");
const SkyCoord = star_math.SkyCoord;
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

    data: []Pixel,
    settings: Settings,

    pub fn init(allocator: *Allocator, settings: Settings) !Canvas {
        var canvas: Canvas = undefined;
        canvas.settings = settings;
        canvas.data = try allocator.alloc(Pixel, canvas.settings.width * canvas.settings.height);
        for (canvas.data) |*p| {
            p.* = Pixel{};
        }
        return canvas;
    }

    pub fn resetImageData(canvas: *Canvas) void {
        @memset(@ptrCast([*]u8, canvas.data.ptr), 0, canvas.data.len * @sizeOf(Pixel));
    }

    pub fn setPixelAt(self: *Canvas, point: Point, new_pixel: Pixel) void {
        if (std.math.isNan(point.x) or std.math.isNan(point.y)) {
            return;
        }

        if (point.x < 0 or point.y < 0) return;
        if (point.x > @intToFloat(f32, self.settings.width) or point.y > @intToFloat(f32, self.settings.height)) return;

        const x = @floatToInt(usize, point.x);
        const y = @floatToInt(usize, point.y);

        const p_index: usize = (y * @intCast(usize, self.settings.width)) + x;
        if (p_index >= self.data.len) return;

        self.data[p_index] = new_pixel;
    }

    pub fn coordToPoint(canvas: Canvas, sky_coord: SkyCoord, local_sidereal_time: f64, sin_latitude: f32, cos_latitude: f32, filter_below_horizon: bool) ?Point {
        const two_pi = comptime math.pi * 2.0;

        const hour_angle = local_sidereal_time - @as(f64, sky_coord.right_ascension);
        const hour_angle_rad = math_utils.floatMod(math_utils.degToRad(hour_angle), two_pi);

        const declination_rad = @floatCast(f64, math_utils.degToRad(sky_coord.declination));
        const sin_dec = math.sin(declination_rad);
        
        const sin_alt = sin_dec * sin_latitude + math.cos(declination_rad) * cos_latitude * math.cos(hour_angle_rad);
        const altitude = math.asin(sin_alt);
        if (filter_below_horizon and altitude < 0) {
            return null;
        }

        const cos_azi = (sin_dec - math.sin(altitude) * sin_latitude) / (math.cos(altitude) * cos_latitude);
        const azi = math.acos(cos_azi);
        const azimuth = if (math.sin(hour_angle_rad) < 0) azi else two_pi - azi;

        const canvas_point = blk: {
            const radius = comptime 2.0 / math.pi;
            // s is the distance from the center of the projection circle to the point
            // aka 1 - the angular distance along the surface of the sky sphere
            const s = 1.0 - (radius * altitude);

            // Convert from polar to cartesian coordinates
            break :blk Point{ 
                // @note without negating x here, the whole chart is rendered backwards. Not sure if this is where the negations
                // is SUPPOSED to go, or if I messed up a negation somewhere else and this is just a hack that makes it work
                .x = -@floatCast(f32, s * math.sin(azimuth)), 
                .y = @floatCast(f32, s * math.cos(azimuth))
            };
        };

        return canvas.translatePoint(canvas_point);
    }

    pub fn pointToCoord(canvas: Canvas, point: Point, observer_pos: ObserverPosition) ?SkyCoord {
        if (!canvas.isInsideCircle(point)) return null;

        const raw_point = canvas.untranslatePoint(point);
        // Distance from raw_point to the center of the sky circle
        const s = math.sqrt(math.pow(f32, raw_point.x, 2.0) + math.pow(f32, raw_point.y, 2.0));
        const altitude = (math.pi * (1 - s)) / 2;

        const observer_lat_rad = math_utils.degToRad(observer_pos.latitude);
        const sin_lat = math.sin(observer_lat_rad);
        const cos_lat = math.cos(observer_lat_rad);

        const declination = math.asin(((raw_point.y / s) * math.cos(altitude) * cos_lat) + (math.sin(altitude) * sin_lat));

        var hour_angle_rad = math.acos((math.sin(altitude) - (math.sin(declination) * sin_lat)) / (math.cos(declination) * cos_lat));

        hour_angle_rad = if (raw_point.x < 0) -hour_angle_rad else hour_angle_rad;

        const hour_angle = math_utils.radToDeg(hour_angle_rad);
        const lst = observer_pos.localSiderealTime();
        const right_ascension = math_utils.floatMod(lst - hour_angle, 360);

        return SkyCoord{
            .right_ascension = @floatCast(f32, right_ascension),
            .declination = math_utils.radToDeg(declination)
        };
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

    pub fn untranslatePoint(self: Canvas, pt: Point) Point {
        const center = Point{
            .x = @intToFloat(f32, self.settings.width) / 2.0,
            .y = @intToFloat(f32, self.settings.height) / 2.0
        };
        const direction_modifier: f32 = if (self.settings.draw_north_up) 1.0 else -1.0;
        const translate_factor: f32 = direction_modifier * self.settings.background_radius * self.settings.zoom_factor;

        return Point{
            .x = (pt.x - center.x) / translate_factor,
            .y = (pt.y - center.y) / -translate_factor
        };
    }

    pub fn isInsideCircle(self: Canvas, point: Point) bool {
        const center = Point{
            .x = @intToFloat(f32, self.settings.width) / 2.0,
            .y = @intToFloat(f32, self.settings.height) / 2.0,
        };

        return point.getDist(center) <= self.settings.background_radius;
    }

    pub fn drawLine(self: *Canvas, line: Line, color: Pixel, thickness: u32) void {
        const num_points = @floatToInt(u32, 75 * self.settings.zoom_factor);
        const is_a_inside_circle = self.isInsideCircle(line.a);
        const start = if (is_a_inside_circle) line.a else line.b;
        const end = if (is_a_inside_circle) line.b else line.a;

        const expand_x = line.getSlope() > 1.5;

        const total_dist = start.getDist(end);
        var point_index: u32 = 0;
        while (point_index < num_points) : (point_index += 1) {
            const point_dist = (total_dist / @intToFloat(f32, num_points)) * @intToFloat(f32, point_index);
            var next_point = Point{
                .x = start.x + (point_dist / total_dist) * (end.x - start.x),
                .y = start.y + (point_dist / total_dist) * (end.y - start.y)
            };
            var width_index: u32 = 0;
            while (width_index < thickness) : (width_index += 1) {
                if (expand_x) {
                    next_point.x += 1; 
                } else {
                    next_point.y += 1;
                }
                if (self.isInsideCircle(next_point)) {
                    self.setPixelAt(next_point, color);
                } else break;
            }
        }
    }

};

test "translate point" {
    const canvas_settings = Canvas.Settings{
        .width = 700,
        .height = 700,
        .draw_north_up = true,
        .background_radius = 0.45 * 700.0,
        .zoom_factor = 1.0,
        .draw_asterisms = false,
        .draw_constellation_grid = false,
    };

    var canvas = try Canvas.init(std.testing.allocator, canvas_settings);
    defer std.testing.allocator.free(canvas.data);
    
    const point = Point{
        .x = 0.5,
        .y = -0.3
    };

    const translated_point = canvas.translatePoint(point);
    const untranslated_point = canvas.untranslatePoint(translated_point);

    std.testing.expectWithinMargin(untranslated_point.x, point.x, 0.005);
    std.testing.expectWithinMargin(untranslated_point.y, point.y, 0.005);

}