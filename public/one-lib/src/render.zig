const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub const Point = struct {
    x: f32,
    y: f32,

    fn getDist(self: Point, other: Point) f32 {
        return std.math.sqrt(std.math.pow(f32, self.x - other.x, 2.0) + std.math.pow(f32, self.y - other.y, 2.0));
    }
};

pub const Canvas = struct {
    pub const Settings = packed struct {
        width: u32,
        height: u32,
        background_radius: f32,
        zoom_factor: f32,
        draw_north_up: bool,
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

    pub fn isInsideCircle(self: *Canvas, point: Point) bool {
        const center = Point{
            .x = @intToFloat(f32, self.settings.width) / 2.0,
            .y = @intToFloat(f32, self.settings.height) / 2.0,
        };

        return point.getDist(center) <= self.settings.background_radius;
    }

    pub fn drawLine(self: *Canvas, a: Point, b: Point) void {
        const line_color = Pixel.rgba(255, 245, 194, 125);
        // const line_color = Pixel.rgb(255, 0, 0);
        const num_points = 500;
        const total_dist = a.getDist(b);
        var point_index: u32 = 0;
        while (point_index < num_points) : (point_index += 1) {
            const point_dist = (total_dist / @intToFloat(f32, num_points)) * @intToFloat(f32, point_index);
            const next_point = Point{
                .x = a.x + (point_dist / total_dist) * (b.x - a.x),
                .y = a.y + (point_dist / total_dist) * (b.y - a.y)
            };
            if (self.isInsideCircle(next_point)) {
                self.setPixelAt(next_point, line_color);
            } else break;
        }
    }

};