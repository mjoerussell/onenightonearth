// @todo Improve testing - find online calculators for star functions and compare against them (fingers crossed)
// @fixme There's some flickering going on in the middle of the window while time-travelling
//        This might actually be something that's happening across the whole vertical line from center up to the edge
const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectWithinEpsilon = std.testing.expectWithinEpsilon;
const expectWithinMargin = std.testing.expectWithinMargin;

pub const Pixel = packed struct {
    a: u8 = 0,
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

pub const CanvasSettings = packed struct {
    width: u32,
    height: u32,
    background_radius: f32,
    zoom_factor: f32,
    draw_north_up: bool,

    fn translatePoint(self: CanvasSettings, pt: CanvasPoint) CanvasPoint {
        const center_x: f32 = @intToFloat(f32, self.width) / 2.0;
        const center_y: f32 = @intToFloat(f32, self.height) / 2.0;

        // A multiplier used to convert a coordinate between [-1, 1] to a coordinate on the actual canvas, taking into
        // account the rendering modifiers that can change based on the user zooming in/out or the travelling moving across poles
        const direction_modifier: f32 = if (self.draw_north_up) 1.0 else -1.0;
        const translate_factor: f32 = direction_modifier * self.background_radius * self.zoom_factor;

        return .{
            .x = center_x + (translate_factor * pt.x),
            .y = center_y - (translate_factor * pt.y),
            .brightness = pt.brightness
        };
    }
};

pub const CanvasPoint = packed struct {
    x: f32,
    y: f32,
    brightness: f32 = 0.0,
};

pub const Coord = packed struct {
    latitude: f32,
    longitude: f32,
};

pub const Star = struct {
    name: []const u8,
    right_ascension: f32 = 0.0,
    declination: f32 = 0.0,
    brightness: f32 = 0.0,
};

pub const StarCoord = packed struct {
    right_ascension: f32,
    declination: f32,
};

pub const ConstellationBranch = packed struct {
    a: StarCoord,
    b: StarCoord
};

pub var global_stars: []Star = undefined;
pub var global_canvas: CanvasSettings = .{
    .width = 700,
    .height = 700,
    .background_radius = 0.45 * 700.0,
    .zoom_factor = 1.0,
    .draw_north_up = true
};

pub var global_pixel_data: []Pixel = undefined;

pub const InitError = error {
    OutOfMemory,
    ParseRA,
    ParseDec,
    ParseMag
};

pub fn initStarData(allocator: *Allocator, star_data: []const u8) InitError!usize {
    var star_list = std.ArrayList(Star).init(allocator);
    var entry_number: u32 = 0;
    var entry_start_index: usize = 0;
    var star: Star = undefined;
    for (star_data) |current_char, current_index| {
        switch (current_char) {
            '\n' => {
                if (star.brightness > 0.35) {
                    star.brightness = math.round(star.brightness * 100.0) / 100.0;
                    try star_list.append(star);
                }
                entry_number = 0;
                entry_start_index = current_index + 1;
            },
            '|' => {
                if (entry_number > 13) continue;
                const value = star_data[entry_start_index..current_index];
                switch (entry_number) {
                    0 => star.name = value,
                    // 0 => star.name = try std.fmt.allocPrint(allocator, "{}", .{value}),
                    1 => star.right_ascension = std.fmt.parseFloat(f32, value) catch |_| return error.ParseRA,
                    5 => star.declination = std.fmt.parseFloat(f32, value) catch |_| return error.ParseDec,
                    13 => {
                        const v_mag = std.fmt.parseFloat(f32, value) catch |_| 0.0;
                        const dimmest_visible: f32 = 18.6;
                        const brightest_value: f32 = -4.6;
                        const mag_display_factor = (dimmest_visible - (v_mag - brightest_value)) / dimmest_visible;
                        star.brightness = mag_display_factor;
                    },
                    else => {}
                }
                entry_number += 1;
                entry_start_index = current_index + 1;
            },
            else => {},
        }
    }
    global_stars = star_list.toOwnedSlice();

    const S = struct {
        fn starOrder(context: void, lhs: Star, rhs: Star) bool {
            return lhs.brightness < rhs.brightness;
        }
    };

    // Sorting the list by star brightness improves rendering performance by reducing the number of state changes
    // needed by the canvas (since the fill color alpha changes based on the brightness)
    // std.sort.sort(Star, global_stars, {}, S.starOrder);

    return global_stars.len;
}

pub fn initCanvasData(allocator: *Allocator, canvas_settings: CanvasSettings) !void {
    global_canvas = canvas_settings;
    global_pixel_data = try allocator.alloc(Pixel, global_canvas.width * global_canvas.height);
    for (global_pixel_data) |*p| {
        p.* = Pixel{};
    }
}

fn fieldExists(comptime value: type, comptime field_name: []const u8) bool {
    const info = @typeInfo(value);
    switch (info) {
        .Struct => {
            inline for (info.Struct.fields) |field| {
                if (std.mem.eql(u8, field.name, field_name)) return true;
            }
            return false;
        },
        else => @compileError("Cannot call fieldExists on non-struct type " ++ @typeName(value))
    }
}

// pub fn projectStars(allocator: *Allocator, observer_location: Coord, observer_timestamp: i64, filter_below_horizon: bool) ![]CanvasPoint {
pub fn projectStar(star: Star, observer_location: Coord, observer_timestamp: i64, filter_below_horizon: bool) ?CanvasPoint {
    // @fixme There's still a bug here - For some reason, if stars are in certain locations in the sky they get blinked to (0,0) on the canvas.
    // I'm assuming that a trig function is returning NaN, but I'm not sure. Also not sure if the root cause is here or getProjectedCoord,
    // but either way it's going through this function.
    // var point_list = try std.ArrayList(CanvasPoint).initCapacity(allocator, global_stars.len / 2);
    
    const two_pi = comptime math.pi * 2.0;
    const half_pi = comptime math.pi / 2.0;
    const local_sideral_time = getLocalSideralTime(@intToFloat(f64, observer_timestamp), observer_location.longitude);
    const lat_rad = degToRad(f32, observer_location.latitude);

    // for (global_stars) |star| {
    const hour_angle = local_sideral_time - @as(f64, star.right_ascension);

    const declination_rad = degToRad(f32, star.declination);
    const hour_angle_rad = floatMod(degToRad(f64, hour_angle), two_pi);

    const sin_dec = math.sin(declination_rad);
    const sin_lat = math.sin(lat_rad);
    const cos_lat = math.cos(lat_rad);

    const sin_alt = sin_dec * sin_lat + math.cos(declination_rad) * cos_lat * math.cos(hour_angle_rad);
    const altitude = boundedASin(sin_alt) catch |err| return null;
    if ((filter_below_horizon and altitude < 0) or (!filter_below_horizon and altitude < -(half_pi / 3.0))) {
        // continue;
        return null;
    }

    const cos_azi = (sin_dec - math.sin(altitude) * sin_lat) / (math.cos(altitude) * cos_lat);
    const azi = math.acos(cos_azi);
    const azimuth = if (math.sin(hour_angle_rad) < 0) azi else two_pi - azi;

    var star_point = getProjectedCoord(@floatCast(f32, altitude), @floatCast(f32, azimuth));
    star_point.brightness = star.brightness;
        
        // try point_list.append(global_canvas.translatePoint(star_point));
    // }

    // return point_list.toOwnedSlice();
    return global_canvas.translatePoint(star_point);
}

pub fn getProjectedCoord(altitude: f32, azimuth: f32) CanvasPoint {
    const radius = comptime 2.0 / math.pi;
    // s is the distance from the center of the projection circle to the point
    // aka 1 - the angular distance along the surface of the sky sphere
    const s = 1.0 - (radius * altitude);

    // Convert from polar to cartesian coordinates
    return .{ 
        .x = s * math.sin(azimuth), 
        .y = s * math.cos(azimuth) 
    };
}

/// Find waypoints along the great circle between two coordinates. Each waypoint will be
/// 1/num_waypoints distance beyond the previous coordinate.
pub fn findWaypoints(allocator: *Allocator, f: Coord, t: Coord, num_waypoints: u32) []Coord {
    const quadrant_radians = comptime math.pi / 2.0;
    const circle_radians = comptime math.pi * 2.0;

    const negative_dir = t.longitude < f.longitude and t.longitude > (f.longitude - math.pi);

    const total_distance = findGreatCircleDistance(f, t) catch |err| 0;
    const course_angle = findGreatCircleCourseAngle(f, t, total_distance) catch |err| 0;

    const waypoint_inc = total_distance / @intToFloat(f32, num_waypoints);

    var waypoints: []Coord = allocator.alloc(Coord, num_waypoints) catch unreachable;
    for (waypoints) |*waypoint, i| {
        const waypoint_rel_angle = @intToFloat(f32, i + 1) * waypoint_inc;
        const lat = findWaypointLatitude(f, waypoint_rel_angle, course_angle) catch |err| 0;
        const rel_long = findWaypointRelativeLongitude(f, lat, waypoint_rel_angle) catch |err| 0;

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

    // drag_distance is the angular distance between the starting location and the result location after a single drag
    // 2.5 is a magic number of degrees, picked because it results in what feels like an appropriate drag speed
    // Higher = move more with smaller cursor movements, and vice versa
    const drag_distance = degToRad(f32, 2.5);

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
fn findGreatCircleDistance(f: Coord, t: Coord) !f32 {
    const long_diff = t.longitude - f.longitude;
    const cos_d = math.sin(f.latitude) * math.sin(t.latitude) + math.cos(f.latitude) * math.cos(t.latitude) * math.cos(long_diff);
    return try boundedACos(cos_d);
}

/// Find the course angle of the great circle path between the starting location and destination.
/// The course angle is the angle between the great circle path being travelled and the equator.
/// @param f            - The starting location
/// @param t            - The destination
/// @param angular_dist - The angular distance along the equator between `f` and `t`.
fn findGreatCircleCourseAngle(f: Coord, t: Coord, angular_dist: f32) !f32 {
    var cos_c = (math.sin(t.latitude) - math.sin(f.latitude) * math.cos(angular_dist)) / (math.cos(f.latitude) * math.sin(angular_dist));
    return try boundedACos(cos_c);
}

/// Find the latitude of a waypoint.
/// @param f             - The initial starting coordinate.
/// @param waypoint_dist - The angular distance along the equator that the waypoint is from `f`
/// @param course_angle  - The angle travelled from `f` along the great circle path to the destination.
fn findWaypointLatitude(f: Coord, waypoint_dist: f32, course_angle: f32) !f32 {
    const sin_lat_x = math.sin(f.latitude) * math.cos(waypoint_dist) + math.cos(f.latitude) * math.sin(waypoint_dist) * math.cos(course_angle);
    return try boundedASin(sin_lat_x);
}

/// Find the relative longitude of a waypoint. This is the longitude of the waypoint with `f` as the origin, and an
/// always-positive direction.
/// @param f             - The relative origin
/// @param waypoint_lat  - The latitude of the waypoint.
/// @param waypoint_dist - The angular distance between `f` and the waypoint.
fn findWaypointRelativeLongitude(f: Coord, waypoint_lat: f32, waypoint_dist: f32) !f32 {
    var cos_long_x = (math.cos(waypoint_dist) - math.sin(f.latitude) * math.sin(waypoint_lat)) / (math.cos(f.latitude) * math.cos(waypoint_lat));
    return try boundedACos(cos_long_x);
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

const OperationError = error{NaN};

/// Safely perform acos on a value without worrying about the value being outside of the range [-1.0, 1.0]. The value
/// will be clamped to either end depending on whether it's too high or too low.
fn boundedACos(x: anytype) OperationError!@TypeOf(x) {
    const T = @TypeOf(x);
    // const value: T = if (x >= 1.0)
    //     1.0
    // else if (x <= -1.0)
    //     -1.0
    // else
    //     x;
    const value = switch (T) {
        f32, f64 =>  math.acos(x),
        f128, comptime_float => return math.acos(@floatCast(f64, x)),
        else => @compileError("boundedACos not implemented for type " ++ T),
    };

    if (std.math.isNan(value)) return error.NaN;

    return value;
}

fn boundedASin(x: anytype) OperationError!@TypeOf(x) {
    const T = @TypeOf(x);
    // const value: T = if (x >= 1.0)
    //     1.0
    // else if (x <= -1.0)
    //     -1.0
    // else
    //     x;
    const value = switch (T) {
        f32, f64 => math.asin(x),
        f128, comptime_float => math.asin(@floatCast(f64, x)),
        else => @compileError("boundedACos not implemented for type " ++ T),
    };

    if (std.math.isNan(value)) return error.NaN;

    return value;
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
