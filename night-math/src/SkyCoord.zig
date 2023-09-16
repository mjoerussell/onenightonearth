const std = @import("std");
const math = std.math;

const math_utils = @import("math_utils.zig");
const FixedPoint = @import("fixed_point.zig").DefaultFixedPoint;

const Coord = @import("star_math.zig").Coord;

const SkyCoord = @This();

pub const ExternSkyCoord = extern struct {
    right_ascension: i16,
    declination: i16,

    pub inline fn unsafeSliceCast(data: []const u8) []const ExternSkyCoord {
        var result: []const ExternSkyCoord = undefined;
        result.ptr = @as([*]const ExternSkyCoord, @ptrCast(@alignCast(data.ptr)));
        result.len = data.len / @sizeOf(ExternSkyCoord);
        return result;
    }

    pub fn toSkyCoord(sky_coord: ExternSkyCoord) SkyCoord {
        return SkyCoord{
            .right_ascension = FixedPoint.toFloat(sky_coord.right_ascension),
            .declination = FixedPoint.toFloat(sky_coord.declination),
        };
    }
};

right_ascension: f32 = 0,
declination: f32 = 0,

pub fn getCoord(sky_coord: SkyCoord, observer_timestamp: i64) Coord {
    const partial_lst = getPartialLocalSiderealTime(observer_timestamp);
    var longitude = sky_coord.right_ascension - partial_lst;

    return Coord{ .latitude = sky_coord.declination, .longitude = longitude };
}

pub fn getVector(sky_coord: SkyCoord, local_sidereal_time: f32) [3]f32 {
    const hour_angle = local_sidereal_time - sky_coord.right_ascension;

    const sin_alt = math.cos(sky_coord.declination) * math.cos(hour_angle);
    const altitude = math.asin(sin_alt);

    const cos_azi = math.sin(sky_coord.declination) / math.cos(altitude);
    const azimuth = math.acos(cos_azi);
    // const azimuth = if (math.sin(hour_angle) < 0) azi else two_pi - azi;

    var result: [3]f32 = [_]f32{ 0, 0, 0 };
    result[0] = math.cos(altitude) * math.cos(azimuth); // x
    result[1] = math.cos(altitude) * math.sin(azimuth); // y
    result[2] = math.sin(altitude); // z

    return result;
}

fn getPartialLocalSiderealTime(timestamp: i64) f32 {
    const j2000_offset_millis = 949_428_000_000;
    const days_since_j2000 = @as(f64, @floatFromInt(timestamp - j2000_offset_millis)) / 86_400_000.0;
    const lst = ((100.46 + (0.985647 * days_since_j2000) + @as(f64, @floatFromInt(15 * timestamp))) * (math.pi / 180.0));
    return @as(f32, @floatCast(math_utils.floatMod(lst, 2 * math.pi)));
}
