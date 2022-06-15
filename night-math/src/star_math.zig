// @todo Improve testing - find online calculators for star functions and compare against them (fingers crossed)
const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;
const assert = std.debug.assert;
const log = @import("./log.zig");

const Canvas = @import("./Canvas.zig");
const Pixel = Canvas.Pixel;

const math_utils = @import("./math_utils.zig");
const Point = math_utils.Point;
const Line = math_utils.Line;

const FixedPoint = @import("fixed_point.zig").DefaultFixedPoint;

const Constellation = @import("Constellation.zig");

pub const Coord = packed struct {
    latitude: f32,
    longitude: f32,
};

pub const SkyCoord = packed struct {
    right_ascension: i16 = 0,
    declination: i16 = 0,

    pub fn getCoord(sky_coord: SkyCoord, observer_timestamp: i64) Coord {
        const partial_lst = getPartialLocalSiderealTime(observer_timestamp);
        var longitude = FixedPoint.toFloat(sky_coord.right_ascension) - partial_lst;

        return Coord{
            .latitude = FixedPoint.toFloat(sky_coord.declination),
            .longitude = longitude
        };
    }
};

pub const ObserverPosition = struct {
    latitude: f32,
    longitude: f32,
    timestamp: i64,

    pub fn localSiderealTime(pos: ObserverPosition) f32 {
        return getPartialLocalSiderealTime(pos.timestamp) + pos.longitude;
    }
};

fn getPartialLocalSiderealTime(timestamp: i64) f32 {
    const j2000_offset_millis = 949_428_000_000;
    const days_since_j2000 = @intToFloat(f64, timestamp - j2000_offset_millis) / 86_400_000.0;
    const lst = ((100.46 + (0.985647 * days_since_j2000) + @intToFloat(f64, 15 * timestamp)) * (math.pi / 180.0));
    return @floatCast(f32, math_utils.floatMod(lst, 2 * math.pi));
}

/// Get the constellation that's currently at the point on the canvas.
pub fn getConstellationAtPoint(canvas: Canvas, point: Point, constellations: []Constellation, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32) ?usize {
    if (!canvas.isInsideCircle(point)) return null;

    for (constellations) |c, constellation_index| {
        if (canvas.settings.zodiac_only and !c.is_zodiac) continue;
        
        if (c.isPointInside(canvas, point, local_sidereal_time, sin_latitude, cos_latitude)) {
            return constellation_index;
        }
    }

    return null;
}

pub fn dragAndMove(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32, drag_speed: f32) Coord {
    const dist_x = drag_end_x - drag_start_x;
    const dist_y = drag_end_y - drag_start_y;

    // Angle between the starting point and the end point
    // Usually atan2 is used with the parameters in the reverse order (atan2(y, x)).
    // The order here (x, y) is intentional, since otherwise horizontal drags would result in vertical movement
    // and vice versa
    // @todo Maybe hack to fix issue with backwards display? See getProjectedCoord
    const dist_phi = -math.atan2(f32, dist_x, dist_y);

    // drag_distance is the angular distance between the starting location and the result location after a single drag
    // Higher = move more with smaller cursor movements, and vice versa
    const drag_distance: f32 = drag_speed * (math.pi / 180.0);

    // Calculate asin(new_latitude), and clamp the result between [-1, 1]
    var sin_lat_x = math.sin(drag_distance) * math.cos(dist_phi);
    if (sin_lat_x > 1.0) {
        sin_lat_x = 1.0;
    } else if (sin_lat_x < -1.0) {
        sin_lat_x = -1.0;
    }

    const new_latitude = math.asin(sin_lat_x);

    // Calculate acos(new_relative_longitude) and clamp the result between [-1, 1]
    var cos_long_x = math.cos(drag_distance) / math.cos(new_latitude);
    if (cos_long_x > 1.0) {
        cos_long_x = 1.0;
    } else if (cos_long_x < -1.0) {
        cos_long_x = -1.0;
    }

    const new_relative_longitude = if (dist_phi < 0.0) -math.acos(cos_long_x) else math.acos(cos_long_x);

    return .{
        .latitude = new_latitude,
        .longitude = new_relative_longitude,
    };
}

