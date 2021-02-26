const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const log = @import("./log.zig").log;
const math_utils = @import("./math_utils.zig");
const matrix = @import("./matrix.zig");
const Point = math_utils.Point;
const Line = math_utils.Line;

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
        fov: f32,
        draw_north_up: bool,
        draw_constellation_grid: bool,
        draw_asterisms: bool
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

    pub fn getProjectionMatrix(self: *Canvas) matrix.Mat4f {
        return matrix.Mat3D.getPerspective(self.settings.fov, @intToFloat(f32, self.settings.width) / @intToFloat(f32, self.settings.height), 1, 4000);
        // return matrix.Mat3D.getOrthographic(0, 0, @intToFloat(f32, self.settings.width), @intToFloat(f32, self.settings.height), 1, 4000);
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

    pub fn translatePoint(self: *Canvas, pt: Point) Point {
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

    pub fn untranslatePoint(self: *Canvas, pt: Point) Point {
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

    pub fn isInsideCircle(self: *Canvas, point: Point) bool {
        const center = Point{
            .x = @intToFloat(f32, self.settings.width) / 2.0,
            .y = @intToFloat(f32, self.settings.height) / 2.0,
        };

        return point.getDist(center) <= self.settings.background_radius;
    }

    pub fn isInsidePolygon(self: *Canvas, polygon: []Point, point: Point) bool {
        const point_ray = Line{
            .a = point,
            .b = Point{ .x = @intToFloat(f32, self.settings.width), .y = point.y }
        };
        var num_intersections: u32 = 0;
        var index: usize = 0;
        while (index < polygon.len - 1) : (index += 1) {
            const bound = Line{
                .a = polygon[index],
                .b = polygon[index + 1]
            };

            if (point_ray.intersection(bound)) |inter_point| {
                const bound_min_x = std.math.min(bound.a.x, bound.b.x);
                const bound_max_x = std.math.max(bound.a.x, bound.b.x);
                if (inter_point.x >= bound_min_x and inter_point.x <= bound_max_x) {
                    self.drawSquare(inter_point, 4, Pixel.rgb(255, 0, 0));
                    num_intersections += 1;
                }
            }
        }
        return num_intersections % 2 == 1;
    }

    pub fn drawSquare(self: *Canvas, p: Point, width: usize, color: Pixel) void {
        var index: f32 = 0;
        var w = @intToFloat(f32, width);
        while (index < w) : (index += 1) {
            self.setPixelAt(Point{ .x = p.x + index, .y = p.y }, color);
            self.setPixelAt(Point{ .x = p.x + index, .y = p.y + (w - 1) }, color);
            self.setPixelAt(Point{ .x = p.x, .y = p.y + index }, color);
            self.setPixelAt(Point{ .x = p.x + (w - 1), .y = p.y + index }, color);
        }
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
        .fov = 40,
        .drag_speed = 2.5,
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