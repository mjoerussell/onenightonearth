// @todo Clean up this code, separate into main functions - wasm interface
// @todo Improve testing - find online calculators for star functions and compare against them (fingers crossed)
// @fixme There's some flickering going on in the middle of the window while time-travelling
//        This might actually be something that's happening across the whole vertical line from center up to the edge

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectWithinEpsilon = std.testing.expectWithinEpsilon;
const expectWithinMargin = std.testing.expectWithinMargin;
const math = std.math;

pub const CanvasPoint = packed struct {
    x: f32,
    y: f32,
    brightness: f32,
};

pub const Coord = packed struct {
    latitude: f32,
    longitude: f32,
};

pub const Star = packed struct {
    right_ascension: f32,
    declination: f32,
    brightness: f32,
};

pub fn projectStars(allocator: *Allocator, stars: []const Star, observer_location: Coord, observer_timestamp: i64) ![]CanvasPoint {
    const two_pi = comptime math.pi * 2.0;
    const local_sideral_time = getLocalSideralTime(@intToFloat(f64, observer_timestamp), observer_location.longitude);

    const points: []CanvasPoint = try allocator.alloc(CanvasPoint, stars.len);
    var num_points: u32 = 0;
    for (stars) |star, i| {
        const hour_angle = local_sideral_time - @as(f64, star.right_ascension);

        const declination_rad = degToRad(f32, star.declination);
        const lat_rad = degToRad(f32, observer_location.latitude);
        const hour_angle_rad = floatMod(degToRad(f64, hour_angle), two_pi);

        const sin_dec = math.sin(declination_rad);
        const sin_lat = math.sin(lat_rad);
        const cos_lat = math.cos(lat_rad);

        const sin_alt = sin_dec * sin_lat + math.cos(declination_rad) * cos_lat * math.cos(hour_angle_rad);
        const altitude = boundedASin(sin_alt);
        if (altitude < 0) {
            continue;
        }

        const cos_azi = (sin_dec - math.sin(altitude) * sin_lat) / (math.cos(altitude) * cos_lat);
        const azi = math.acos(cos_azi);
        const azimuth = if (math.sin(hour_angle_rad) < 0) azi else two_pi - azi;

        const star_point = getProjectedCoord(@floatCast(f32, altitude), @floatCast(f32, azimuth), star.brightness);

        points[num_points] = star_point;
        num_points += 1;
    }

    return allocator.realloc(points, num_points) catch |err| return points;
}

pub fn getProjectedCoord(altitude: f32, azimuth: f32, brightness: f32) CanvasPoint {
    const radius = comptime 2.0 / math.pi;
    const quarter_rad = comptime math.pi / 2.0;
    const s = 1.0 - (radius * altitude);
    const rho = floatMod(azimuth, quarter_rad);
    const quadrant = math.floor(azimuth / quarter_rad);

    var x: f32 = 0;
    var y: f32 = 0;
    if (quadrant == 0) {
        x = s * math.sin(rho);
        y = s * math.cos(rho);
    } else if (quadrant == 1) {
        x = s * math.cos(rho);
        y = -1 * s * math.sin(rho);
    } else if (quadrant == 2) {
        x = -1 * s * math.sin(rho);
        y = -1 * s * math.cos(rho);
    } else if (quadrant == 3) {
        x = -1 * s * math.cos(rho);
        y = s * math.sin(rho);
    }

    return .{ .x = x, .y = y, .brightness = brightness };
}

pub fn findWaypoints(allocator: *Allocator, f: Coord, t: Coord, num_waypoints: u32) []Coord {
    const quadrant_radians = comptime math.pi / 2.0;
    const circle_radians = comptime math.pi * 2.0;

    const negative_dir = t.longitude < f.longitude and t.longitude > (f.longitude - math.pi);

    const total_distance = findGreatCircleDistance(f, t);
    const course_angle = findGreatCircleCourseAngle(f, t, total_distance);

    const waypoint_inc = total_distance / @intToFloat(f32, num_waypoints);

    var waypoints: []Coord = allocator.alloc(Coord, num_waypoints) catch unreachable;
    for (waypoints) |*waypoint, i| {
        const waypoint_rel_angle = @intToFloat(f32, i + 1) * waypoint_inc;
        const lat = findWaypointLatitude(f, waypoint_rel_angle, course_angle);
        const rel_long = findWaypointRelativeLongitude(f, lat, waypoint_rel_angle);

        const long = if (negative_dir) f.longitude - rel_long else f.longitude + rel_long;

        waypoint.* = Coord{ .latitude = lat, .longitude = long };
    }

    return waypoints;
}

pub fn dragAndMove(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) Coord {
    const dist_x = drag_end_x - drag_start_x;
    const dist_y = drag_end_y - drag_start_y;

    // Angle between the starting point and the end point
    // Usually atan2 is used with the parameters in the reverse order (atan2(y, x)).
    // The order here (x, y) is intentional, since otherwise horizontal drags would result in vertical movement
    // and vice versa
    const dist_phi = math.atan2(f32, dist_x, dist_y);

    // cast comptime_float to f32
    const zero: f32 = 0.0;
    // drag_distance is the angular distance between the starting location and the result location after a single drag
    // 2.3 is a magic number of degrees, picked because it results in what feels like an appropriate drag speed
    // Higher = move more with smaller cursor movements, and vice versa
    const drag_distance = degToRad(f32, 2.3);

    // Calculate asin(new_latitude), and clamp the result between [-1, 1]
    var sin_lat_x = math.sin(zero) * math.cos(drag_distance) + math.cos(zero) * math.sin(drag_distance) * math.cos(dist_phi);
    if (sin_lat_x > 1.0) {
        sin_lat_x = 1.0;
    } else if (sin_lat_x < -1.0) {
        sin_lat_x = -1.0;
    }

    const new_latitude = math.asin(sin_lat_x);

    // Calculate acos(new_relative_longitude) and clamp the result between [-1, 1]
    var cos_long_x = (math.cos(drag_distance) - math.sin(zero) * math.sin(new_latitude)) / (math.cos(zero) * math.cos(new_latitude));
    if (cos_long_x > 1.0) {
        cos_long_x = 1.0;
    } else if (cos_long_x < -1.0) {
        cos_long_x = -1.0;
    }

    var new_relative_longitude = radToDegLong(math.acos(cos_long_x));
    new_relative_longitude = if (dist_phi < 0.0) -new_relative_longitude else new_relative_longitude;

    return .{
        .latitude = radToDeg(new_latitude),
        .longitude = new_relative_longitude,
    };
}

fn getLocalSideralTime(current_timestamp: f64, longitude: f64) f64 {
    // The number of milliseconds between January 1st, 1970 and the J2000 epoch
    const j2000_offset_millis: f64 = 949_428_000_000.0;
    const days_since_j2000 = (current_timestamp - j2000_offset_millis) / 86400000.0;
    return 100.46 + (0.985647 * days_since_j2000) + longitude + (15.0 * current_timestamp);
}

/// Find the angular distance along the equator between two points on the surface.
/// @param f - The starting location.
/// @param t - The ending location.
fn findGreatCircleDistance(f: Coord, t: Coord) f32 {
    const long_diff = t.longitude - f.longitude;
    const cos_d = math.sin(f.latitude) * math.sin(t.latitude) + math.cos(f.latitude) * math.cos(t.latitude) * math.cos(long_diff);
    return boundedACos(cos_d);
}

/// Find the course angle of the great circle path between the starting location and destination.
/// The course angle is the angle between the great circle path being travelled and the equator.
/// @param f            - The starting location
/// @param t            - The destination
/// @param angular_dist - The angular distance along the equator between `f` and `t`.
fn findGreatCircleCourseAngle(f: Coord, t: Coord, angular_dist: f32) f32 {
    var cos_c = (math.sin(t.latitude) - math.sin(f.latitude) * math.cos(angular_dist)) / (math.cos(f.latitude) * math.sin(angular_dist));
    return boundedACos(cos_c);
}

/// Find the latitude of a waypoint.
/// @param f             - The initial starting coordinate.
/// @param waypoint_dist - The angular distance along the equator that the waypoint is from `f`
/// @param course_angle  - The angle travelled from `f` along the great circle path to the destination.
fn findWaypointLatitude(f: Coord, waypoint_dist: f32, course_angle: f32) f32 {
    const sin_lat_x = math.sin(f.latitude) * math.cos(waypoint_dist) + math.cos(f.latitude) * math.sin(waypoint_dist) * math.cos(course_angle);
    return boundedASin(sin_lat_x);
}

/// Find the relative longitude of a waypoint. This is the longitude of the waypoint with `f` as the origin, and an
/// always-positive direction.
/// @param f             - The relative origin
/// @param waypoint_lat  - The latitude of the waypoint.
/// @param waypoint_dist - The angular distance between `f` and the waypoint.
fn findWaypointRelativeLongitude(f: Coord, waypoint_lat: f32, waypoint_dist: f32) f32 {
    var cos_long_x = (math.cos(waypoint_dist) - math.sin(f.latitude) * math.sin(waypoint_lat)) / (math.cos(f.latitude) * math.cos(waypoint_lat));
    return boundedACos(cos_long_x);
}

/// A radian-to-degree converter specialized for longitude values.
/// If the resulting degree value would be greater than 180 degrees,
/// 360 degrees will be subtracted - meaning that this function returns
/// values in a range of [-180, 180] degrees.
fn radToDegLong(radian: f32) f32 {
    const deg = radToDeg(radian);
    if (deg > 180.0) {
        return deg - 360.0;
    } else {
        return deg;
    }
}

/// A standard degree-to-radian conversion function.
fn degToRad(comptime T: type, degree: T) T {
    return degree * (math.pi / 180.0);
}

/// A standard radian-to-degree conversion function.
fn radToDeg(radian: f32) f32 {
    return radian * (180.0 / math.pi);
}

/// Safely perform acos on a value without worrying about the value being outside of the range [-1.0, 1.0]. The value
/// will be clamped to either end depending on whether it's too high or too low.
fn boundedACos(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    const value: T = if (x >= 1.0)
        1.0
    else if (x <= -1.0)
        -1.0
    else
        x;
    switch (T) {
        f32, f64 => {
            return math.acos(value);
        },
        f128, comptime_float => {
            return math.acos(@floatCast(f64, value));
        },
        else => @compileError("boundedACos not implemented for type " ++ T),
    }
}

fn boundedASin(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    const value: T = if (x >= 1.0)
        1.0
    else if (x <= -1.0)
        -1.0
    else
        x;
    switch (T) {
        f32, f64 => {
            return math.asin(value);
        },
        f128, comptime_float => {
            return math.asin(@floatCast(f64, value));
        },
        else => @compileError("boundedACos not implemented for type " ++ T),
    }
}

fn FloatModResult(comptime input_type: type) type {
    return switch (input_type) {
        f32 => f32,
        f64 => f64,
        f128 => f128,
        comptime_float => f128,
        else => @compileError("floatMod is not implemented for type " ++ @typeName(input_type)),
    };
}

fn floatMod(num: anytype, denom: @TypeOf(num)) FloatModResult(@TypeOf(num)) {
    const T = @TypeOf(num);
    comptime assert(T == f32 or T == f64 or T == f128 or T == comptime_float);

    // comptime_float is not compatable with math.fabs, so cast to f128 before using
    const numerator = if (T == comptime_float) @floatCast(f128, num) else num;
    const denominator = if (T == comptime_float) @floatCast(f128, denom) else denom;

    const div = math.floor(math.absFloat(numerator / denominator));
    const whole_part = math.absFloat(denominator) * div;

    return if (num < 0) num + whole_part else num - whole_part;
}

test "degree to radian conversion" {
    const epsilon = 0.001;
    const degree = 45.0;
    const radian = comptime degToRad(f32, degree);
    expectWithinEpsilon(math.pi / 4.0, radian, epsilon);
}

test "radian to degree conversion" {
    const epsilon = 0.001;
    const degree = comptime radToDeg(math.pi / 4.0);
    expectWithinEpsilon(45.0, degree, epsilon);
}

test "longitude back and forth conversion - negative" {
    const epsilon = 0.001;
    const degLong = -75.0;
    const radLong = comptime degToRad(f32, degLong);
    const backDegLong = comptime radToDegLong(radLong);
    expectWithinEpsilon(-degLong, -backDegLong, epsilon);
}

test "custom float modulus" {
    const margin = 0.0001;
    expectEqual(1.0, comptime floatMod(4.0, 1.5));
    expectWithinMargin(1.3467, comptime floatMod(74.17405, 14.56547), margin);
    expectWithinMargin(1.3467, comptime floatMod(74.17405, -14.56547), margin);
    expectWithinMargin(-1.3467, comptime floatMod(-74.17405, -14.56547), margin);
    expectWithinMargin(-1.3467, comptime floatMod(-74.17405, 14.56547), margin);
}
