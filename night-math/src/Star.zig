const std = @import("std");
const math = std.math;

const FixedPoint = @import("fixed_point.zig").DefaultFixedPoint;
const ExternSkyCoord = @import("SkyCoord.zig").ExternSkyCoord;
const Pixel = @import("Canvas.zig").Pixel;

const Star = @This();

pub const ExternStar = packed struct {
    right_ascension: i16,
    declination: i16,
    brightness: u8,
    spec_type: SpectralType,

    pub fn toStar(ext_star: ExternStar) Star {
        const right_ascension = FixedPoint.toFloat(ext_star.right_ascension);
        const declination = FixedPoint.toFloat(ext_star.declination);
        return .{
            .right_ascension = right_ascension,
            .declination = declination,
            .sin_declination = math.sin(declination),
            .cos_declination = math.cos(declination),
            .pixel = ext_star.getColor(),
        };
    }

    pub fn getColor(star: ExternStar) Pixel {
        var base_color = star.spec_type.getColor();
        base_color.a = @intCast(u8, std.math.clamp(@intCast(u16, star.brightness) + 30, 0, @as(u16, 255)));

        return base_color;
    }
};

/// Each star has a spectral type based on its temperature. Each spectral type category emits a different
/// color of light.
pub const SpectralType = enum(u8) {
    /// > 30,000 K
    O,
    /// 10,000 K <> 30,000 K
    B,
    /// 7,500 K <> 10,000 K
    A,
    /// 6,000 K <> 7,500 K
    F,
    /// 5,200 K <> 6,000 K
    G,
    /// 3,700 K <> 5,200 K
    K,
    /// 2,400 K <> 3,700 K
    M,

    pub fn getColor(spec: SpectralType) Pixel {
        return switch (spec) {
            // Blue
            .O => Pixel.rgb(2, 89, 156),
            // Blue-white
            .B => Pixel.rgb(129, 212, 247),
            // White
            .A => Pixel.rgb(255, 255, 255),
            // Yellow-white
            .F => Pixel.rgb(254, 255, 219),
            // Yellow
            .G => Pixel.rgb(253, 255, 112),
            // Orange
            .K => Pixel.rgb(240, 129, 50),
            // Red
            .M => Pixel.rgb(207, 32, 23)
        };
    }
};

right_ascension: f32,
declination: f32,
sin_declination: f32,
cos_declination: f32,
pixel: Pixel,