const std = @import("std");
const math = std.math;

const math_utils = @import("math_utils.zig");
const FixedPoint = @import("fixed_point.zig").DefaultFixedPoint;

const star_math = @import("star_math.zig");
const Coord = star_math.Coord;

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

pub fn fromCoord(coord: Coord, timestamp: i64) SkyCoord {
    return .{
        .right_ascension = coord.longitude + star_math.getPartialLocalSiderealTime(timestamp),
        .declination = coord.latitude,
    };
}

pub fn toCoord(sky_coord: SkyCoord, timestamp: i64) Coord {
    return Coord{
        .longitude = sky_coord.right_ascension - star_math.getPartialLocalSiderealTime(timestamp),
        .latitude = sky_coord.declination,
    };
}

pub fn getVector(sky_coord: SkyCoord, local_sidereal_time: f32) [3]f32 {
    const hour_angle = local_sidereal_time - sky_coord.right_ascension;

    const sin_alt = math.cos(sky_coord.declination) * math.cos(hour_angle);
    const altitude = math.asin(sin_alt);

    const cos_azi = math.sin(sky_coord.declination) / math.cos(altitude);
    const azimuth = math.acos(cos_azi);

    var result: [3]f32 = [_]f32{ 0, 0, 0 };
    result[0] = math.cos(altitude) * math.cos(azimuth); // x
    result[1] = math.cos(altitude) * math.sin(azimuth); // y
    result[2] = math.sin(altitude); // z

    return result;
}
