const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

const Canvas = @import("Canvas.zig");
const Pixel = Canvas.Pixel;

const star_math = @import("star_math.zig");
const ObserverPosition = star_math.ObserverPosition;

const Star = @import("Star.zig");
const Constellation = @import("Constellation.zig");

const StarRenderer = @This();

canvas: Canvas,

stars: std.MultiArrayList(Star),
constellations: []Constellation,

pub fn run(renderer: *StarRenderer, observer: ObserverPosition) void {
    const line_color = Pixel.rgba(255, 245, 194, 175);

    renderer.canvas.projectAndRenderStarsWide(renderer.stars, observer);

    if (renderer.canvas.settings.draw_constellation_grid or renderer.canvas.settings.draw_asterisms) {
        for (renderer.constellations) |constellation| {
            if (renderer.canvas.settings.zodiac_only and !constellation.is_zodiac) continue;

            if (renderer.canvas.settings.draw_constellation_grid) {
                renderer.canvas.drawGrid(constellation, line_color, 1, observer);
            }
            if (renderer.canvas.settings.draw_asterisms) {
                renderer.canvas.drawAsterism(constellation, line_color, 1, observer);
            }
        }
    }
}
