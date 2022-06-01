const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

const log = @import("log.zig");

const Canvas = @import("Canvas.zig");
const Pixel = Canvas.Pixel;

const star_math = @import("star_math.zig");
const ObserverPosition = star_math.ObserverPosition;
const Constellation = star_math.Constellation;

const Star = @import("Star.zig");

const StarRenderer = @This();

canvas: Canvas,
// observer_latitude: f32,
// observer_longitude: f32,
// observer_timestamp: i64,

stars: std.MultiArrayList(Star),
constellations: []star_math.Constellation,

pub fn run(renderer: *StarRenderer, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    const pos = ObserverPosition{ .latitude = observer_latitude, .longitude = observer_longitude, .timestamp = observer_timestamp };
    const local_sidereal_time = pos.localSiderealTime();
    const sin_latitude = std.math.sin(observer_latitude);
    const cos_latitude = std.math.cos(observer_latitude);

    const line_color = Pixel.rgba(255, 245, 194, 175);

    renderer.canvas.projectAndRenderStarsWide(renderer.stars, local_sidereal_time, sin_latitude, cos_latitude);

    if (renderer.canvas.settings.draw_constellation_grid or renderer.canvas.settings.draw_asterisms) {
        for (renderer.constellations) |constellation| {
            if (renderer.canvas.settings.zodiac_only and !constellation.is_zodiac) continue;
            
            if (renderer.canvas.settings.draw_constellation_grid) {
                renderer.canvas.drawGrid(constellation, line_color, 1, local_sidereal_time, sin_latitude, cos_latitude);
            }
            if (renderer.canvas.settings.draw_asterisms) {
                renderer.canvas.drawAsterism(constellation, line_color, 1, local_sidereal_time, sin_latitude, cos_latitude);
            }
        }
    }
}