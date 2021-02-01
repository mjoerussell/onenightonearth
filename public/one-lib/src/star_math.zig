// @todo Improve testing - find online calculators for star functions and compare against them (fingers crossed)
const std = @import("std");
const math_utils = @import("./math_utils.zig");
const render = @import("./render.zig");
const Allocator = std.mem.Allocator;
const math = std.math;
const assert = std.debug.assert;
const Pixel = render.Pixel;
const Point = render.Point;
const Canvas = render.Canvas;

pub const Coord = packed struct {
    latitude: f32,
    longitude: f32,
};

pub const SkyCoord = packed struct {
    right_ascension: f32,
    declination: f32
};

pub const Star = packed struct {
    right_ascension: f32,
    declination: f32,
    brightness: f32,
    spec_type: SpectralType,
};

pub const Constellation = struct {
    boundaries: []SkyCoord,
};

pub const SpectralType = packed enum(u8) {
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
            .B => Pixel.rgb(131, 195, 222),
            // White
            .A => Pixel.rgb(255, 255, 255),
            // Yellow-white
            .F => Pixel.rgb(249, 250, 192),
            // Yellow
            .G => Pixel.rgb(253, 255, 133),
            // Orange
            .K => Pixel.rgb(255, 142, 61),
            // Red
            .M => Pixel.rgb(207, 32, 23)
        };
    }
};

pub fn projectStar(canvas: *Canvas, star: Star, observer_location: Coord, observer_timestamp: i64, filter_below_horizon: bool) void {
    const point = projectToCanvas(
        canvas, 
        SkyCoord{ .right_ascension = star.right_ascension, .declination = star.declination }, 
        observer_location, 
        observer_timestamp, 
        true
    );
    if (point) |p| {
        if (canvas.isInsideCircle(p)) {
            var base_color = star.spec_type.getColor();
            base_color.a = @floatToInt(u8, star.brightness * 255.0); 
            canvas.setPixelAt(p, base_color);
        }
    }
}

pub fn projectConstellation(canvas: *Canvas, constellation: Constellation, observer_location: Coord, observer_timestamp: i64) void {
    var branch_index: usize = 0;
    while (branch_index < constellation.boundaries.len - 1) : (branch_index += 1) {
        const point_a = projectToCanvas(canvas, constellation.boundaries[branch_index], observer_location, observer_timestamp, false);
        const point_b = projectToCanvas(canvas, constellation.boundaries[branch_index + 1], observer_location, observer_timestamp, false);
        
        if (point_a == null or point_b == null) continue;

        canvas.drawLine(point_a.?, point_b.?);
    }

    // Connect final point to first point
    const point_a = projectToCanvas(canvas, constellation.boundaries[constellation.boundaries.len - 1], observer_location, observer_timestamp, false);
    const point_b = projectToCanvas(canvas, constellation.boundaries[0], observer_location, observer_timestamp, false);

    if (point_a == null or point_b == null) return;

    canvas.drawLine(point_a.?, point_b.?);
}

pub fn projectToCanvas(canvas: *Canvas, sky_coord: SkyCoord, observer_location: Coord, observer_timestamp: i64, filter_below_horizon: bool) ?Point {
    const two_pi = comptime math.pi * 2.0;
    const half_pi = comptime math.pi / 2.0;
    const local_sideral_time = getLocalSideralTime(@intToFloat(f64, observer_timestamp), observer_location.longitude);
    const lat_rad = math_utils.degToRad(observer_location.latitude);

    const hour_angle = local_sideral_time - @as(f64, sky_coord.right_ascension);

    const declination_rad = @floatCast(f64, math_utils.degToRad(sky_coord.declination));
    const hour_angle_rad = math_utils.floatMod(math_utils.degToRad(hour_angle), two_pi);

    const sin_dec = math.sin(declination_rad);
    const sin_lat = math.sin(lat_rad);
    const cos_lat = math.cos(lat_rad);

    const sin_alt = sin_dec * sin_lat + math.cos(declination_rad) * cos_lat * math.cos(hour_angle_rad);
    const altitude = math_utils.boundedASin(sin_alt) catch |err| return null;
    if (filter_below_horizon and altitude < 0) {
        return null;
    }

    const cos_azi = (sin_dec - math.sin(altitude) * sin_lat) / (math.cos(altitude) * cos_lat);
    const azi = math.acos(cos_azi);
    const azimuth = if (math.sin(hour_angle_rad) < 0) azi else two_pi - azi;

    return canvas.translatePoint(getProjectedCoord(@floatCast(f32, altitude), @floatCast(f32, azimuth)));
}

pub fn getProjectedCoord(altitude: f32, azimuth: f32) Point {
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
pub fn findWaypoints(allocator: *Allocator, f: Coord, t: Coord) []Coord {
    const quadrant_radians = comptime math.pi / 2.0;
    const circle_radians = comptime math.pi * 2.0;
    const waypoints_per_radian: f32 = 20;

    const t_radian = Coord{
        .latitude = math_utils.degToRad(t.latitude),
        .longitude = math_utils.degToRad(t.longitude)
    };

    const f_radian = Coord{
        .latitude = math_utils.degToRad(f.latitude),
        .longitude = math_utils.degToRad(f.longitude)
    };

    const negative_dir = t_radian.longitude < f_radian.longitude and t_radian.longitude > (f_radian.longitude - math.pi);

    const total_distance = findGreatCircleDistance(f_radian, t_radian) catch |err| 0;
    
    const num_waypoints: usize = 100;
    const waypoint_inc: f32 = total_distance / @intToFloat(f32, num_waypoints);
    const course_angle = findGreatCircleCourseAngle(f_radian, t_radian, total_distance) catch |err| 0;

    var waypoints: []Coord = allocator.alloc(Coord, num_waypoints) catch unreachable;
    for (waypoints) |*waypoint, i| {
        const waypoint_rel_angle = @intToFloat(f32, i + 1) * waypoint_inc;
        const lat = findWaypointLatitude(f_radian, waypoint_rel_angle, course_angle) catch |err| 0;
        const rel_long = findWaypointRelativeLongitude(f_radian, lat, waypoint_rel_angle) catch |err| 0;

        const long = if (negative_dir) f_radian.longitude - rel_long else f_radian.longitude + rel_long;

        waypoint.* = Coord{ 
            .latitude = math_utils.radToDeg(lat), 
            .longitude = math_utils.radToDegLong(long) 
        };
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
    // 2.35 is a magic number of degrees, picked because it results in what feels like an appropriate drag speed
    // Higher = move more with smaller cursor movements, and vice versa
    const drag_distance: f32 = math_utils.degToRad(1.5);

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

    var new_relative_longitude = math_utils.radToDegLong(math.acos(cos_long_x));
    new_relative_longitude = if (dist_phi < 0.0) -new_relative_longitude else new_relative_longitude;

    return .{
        .latitude = math_utils.radToDeg(new_latitude),
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
    return try math_utils.boundedACos(cos_d);
}

/// Find the course angle of the great circle path between the starting location and destination.
/// The course angle is the angle between the great circle path being travelled and the equator.
/// @param f            - The starting location
/// @param t            - The destination
/// @param angular_dist - The angular distance along the equator between `f` and `t`.
fn findGreatCircleCourseAngle(f: Coord, t: Coord, angular_dist: f32) !f32 {
    var cos_c = (math.sin(t.latitude) - math.sin(f.latitude) * math.cos(angular_dist)) / (math.cos(f.latitude) * math.sin(angular_dist));
    return try math_utils.boundedACos(cos_c);
}

/// Find the latitude of a waypoint.
/// @param f             - The initial starting coordinate.
/// @param waypoint_dist - The angular distance along the equator that the waypoint is from `f`
/// @param course_angle  - The angle travelled from `f` along the great circle path to the destination.
fn findWaypointLatitude(f: Coord, waypoint_dist: f32, course_angle: f32) !f32 {
    const sin_lat_x = math.sin(f.latitude) * math.cos(waypoint_dist) + math.cos(f.latitude) * math.sin(waypoint_dist) * math.cos(course_angle);
    return try math_utils.boundedASin(sin_lat_x);
}

/// Find the relative longitude of a waypoint. This is the longitude of the waypoint with `f` as the origin, and an
/// always-positive direction.
/// @param f             - The relative origin
/// @param waypoint_lat  - The latitude of the waypoint.
/// @param waypoint_dist - The angular distance between `f` and the waypoint.
fn findWaypointRelativeLongitude(f: Coord, waypoint_lat: f32, waypoint_dist: f32) !f32 {
    var cos_long_x = (math.cos(waypoint_dist) - math.sin(f.latitude) * math.sin(waypoint_lat)) / (math.cos(f.latitude) * math.cos(waypoint_lat));
    return try math_utils.boundedACos(cos_long_x);
}