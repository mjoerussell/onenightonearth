// @todo Improve testing - find online calculators for star functions and compare against them (fingers crossed)
const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;
const assert = std.debug.assert;
const log = @import("./log.zig").log;
const render = @import("./render.zig");
const Pixel = render.Pixel;
const Canvas = render.Canvas;
const math_utils = @import("./math_utils.zig");
const Point = math_utils.Point;
const Line = math_utils.Line;

const matrix = @import("./matrix.zig");
const Mat3D = matrix.Mat3D;
const Mat4f = matrix.Mat4f;

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
    asterism: []SkyCoord,
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

fn getAlpha(brightness: f32) u8 {
    return if (brightness >= 1.0)
        255
    else if (brightness <= 0) 
        0
    else @floatToInt(u8, brightness * 255.0);
}

pub fn projectStar(canvas: *Canvas, star: Star, observer_location: Coord, observer_timestamp: i64, filter_below_horizon: bool) ?Point {
    return projectToCanvas(
        canvas, 
        SkyCoord{ .right_ascension = star.right_ascension, .declination = star.declination }, 
        observer_location, 
        observer_timestamp, 
        true
    );
}

pub fn projectConstellationGrid(canvas: *Canvas, constellation: Constellation, color: Pixel, line_width: u32, observer_location: Coord, observer_timestamp: i64) void {
    var branch_index: usize = 0;
    while (branch_index < constellation.boundaries.len - 1) : (branch_index += 1) {
        const point_a = projectToCanvas(canvas, constellation.boundaries[branch_index], observer_location, observer_timestamp, false);
        const point_b = projectToCanvas(canvas, constellation.boundaries[branch_index + 1], observer_location, observer_timestamp, false);
        
        if (point_a == null or point_b == null) continue;

        canvas.drawLine(Line{ .a = point_a.?, .b = point_b.?}, color, line_width);
    }

    // Connect final point to first point
    const point_a = projectToCanvas(canvas, constellation.boundaries[constellation.boundaries.len - 1], observer_location, observer_timestamp, false);
    const point_b = projectToCanvas(canvas, constellation.boundaries[0], observer_location, observer_timestamp, false);

    if (point_a == null or point_b == null) return;

    canvas.drawLine(.{ .a = point_a.?, .b = point_b.?}, color, line_width);
}

pub fn projectConstellationAsterism(canvas: *Canvas, constellation: Constellation, color: Pixel, line_width: u32, observer_location: Coord, observer_timestamp: i64) void {
    var branch_index: usize = 0;
    while (branch_index < constellation.asterism.len - 1) : (branch_index += 2) {
        const point_a = projectToCanvas(canvas, constellation.asterism[branch_index], observer_location, observer_timestamp, false);
        const point_b = projectToCanvas(canvas, constellation.asterism[branch_index + 1], observer_location, observer_timestamp, false);
        
        if (point_a == null or point_b == null) continue;

        canvas.drawLine(Line{ .a = point_a.?, .b = point_b.?}, color, line_width);
    }
}

pub fn drawSkyGrid(canvas: *Canvas, observer_location: Coord, observer_timestamp: i64) void {
    const grid_color = Pixel.rgba(91, 101, 117, 180);
    const grid_zero_color = Pixel.rgba(176, 98, 65, 225);
    var base_right_ascension: f32 = 0;

    while (base_right_ascension < 360) : (base_right_ascension += 15) {
        var declination: f32 = -90;
        while (declination <= 90) : (declination += 0.1) {
            const point = projectToCanvas(canvas, .{ .right_ascension = base_right_ascension, .declination = declination }, observer_location, observer_timestamp, true);
            if (point) |p| {
                if (canvas.isInsideCircle(p)) {
                    if (base_right_ascension == 0) {
                        canvas.setPixelAt(p, grid_zero_color);
                    } else {
                        canvas.setPixelAt(p, grid_color);
                    }
                }
            }
        }
    }

    var base_declination: f32 = -90;
    while (base_declination <= 90) : (base_declination += 15) {
        var right_ascension: f32 = 0;
        while (right_ascension <= 360) : (right_ascension += 0.1) {
            const point = projectToCanvas(canvas, .{ .right_ascension = right_ascension, .declination = base_declination }, observer_location, observer_timestamp, true);
            if (point) |p| {
                if (canvas.isInsideCircle(p)) {
                    if (base_declination == 0) {
                        canvas.setPixelAt(p, grid_zero_color);
                    } else {
                        canvas.setPixelAt(p, grid_color);
                    }
                }
            }
        }
    }
}

pub fn projectToCanvas(canvas: *Canvas, sky_coord: SkyCoord, observer_location: Coord, observer_timestamp: i64, filter_below_horizon: bool) ?Point {
    const two_pi = comptime math.pi * 2.0;
    const half_pi = comptime math.pi / 2.0;

    const local_sidereal_time = getLocalSiderealTime(@intToFloat(f64, observer_timestamp), observer_location.longitude);
    const hour_angle = local_sidereal_time - @as(f64, sky_coord.right_ascension);
    const hour_angle_rad = math_utils.floatMod(math_utils.degToRad(hour_angle), two_pi);

    const declination_rad = @floatCast(f64, math_utils.degToRad(sky_coord.declination));
    const sin_dec = math.sin(declination_rad);
    
    const lat_rad = math_utils.degToRad(observer_location.latitude);
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

    return Point{ .x = @floatCast(f32, azimuth), .y = @floatCast(f32, altitude) };
}

pub fn getProjectedCoord(altitude: f32, azimuth: f32) Point {
    const radius = comptime 2.0 / math.pi;
    // s is the distance from the center of the projection circle to the point
    // aka 1 - the angular distance along the surface of the sky sphere
    const s = 1.0 - (radius * altitude);

    // Convert from polar to cartesian coordinates
    return .{ 
        // TODO without negating x here, the whole chart is rendered backwards. Not sure if this is where the negations
        // is SUPPOSED to go, or if I messed up a negation somewhere else and this is just a hack that makes it work
        .x = -(s * math.sin(azimuth)), 
        .y = s * math.cos(azimuth) 
    };
}

pub fn getConstellationAtPoint(canvas: *Canvas, point: Point, constellations: []Constellation, observer_location: Coord, observer_timestamp: i64) ?usize {
    if (!canvas.isInsideCircle(point)) return null;

    const point_ray_right = Line{ 
        .a = point, 
        .b = Point{ .x = @intToFloat(f32, canvas.settings.width), .y = point.y } 
    };
    const point_ray_left = Line{ 
        .a = point, 
        .b = Point{ .x = -@intToFloat(f32, canvas.settings.width), .y = point.y } 
    };

    for (constellations) |c, constellation_index| {
        var b_index: usize = 0;
        var num_intersections_right: u32 = 0;
        var num_intersections_left: u32 = 0;
        while (b_index < c.boundaries.len - 1) : (b_index += 1) {
            const b_a = projectToCanvas(canvas, c.boundaries[b_index], observer_location, observer_timestamp, false);
            const b_b = projectToCanvas(canvas, c.boundaries[b_index + 1], observer_location, observer_timestamp, false);

            if (b_a == null or b_b == null) continue;

            const bound = Line{ .a = b_a.?, .b = b_b.? };
            if (point_ray_right.segmentIntersection(bound)) |inter_point| {
                if (canvas.isInsideCircle(inter_point)) {
                    num_intersections_right += 1;
                }
            }

            if (point_ray_left.segmentIntersection(bound)) |inter_point| {
                if (canvas.isInsideCircle(inter_point)) {
                    num_intersections_left += 1;
                }
            }

        }

        const b_a = projectToCanvas(canvas, c.boundaries[c.boundaries.len - 1], observer_location, observer_timestamp, false);
        const b_b = projectToCanvas(canvas, c.boundaries[0], observer_location, observer_timestamp, false);

        if (b_a == null or b_b == null) continue;

        const bound = Line{ .a = b_a.?, .b = b_b.? };
        if (point_ray_right.segmentIntersection(bound)) |inter_point| {
            if (canvas.isInsideCircle(inter_point)) {
                num_intersections_right += 1;
            }
        }
         if (point_ray_left.segmentIntersection(bound)) |inter_point| {
                if (canvas.isInsideCircle(inter_point)) {
                    num_intersections_left += 1;
                }
            }
        if (
            (num_intersections_left % 2 == 1 and num_intersections_right % 2 == 1)
        ) {
            return constellation_index;
        }
    }
    return null;
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

pub fn dragAndMove(canvas: *Canvas, drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) Coord {
    const dist_x = drag_end_x - drag_start_x;
    const dist_y = drag_end_y - drag_start_y;

    // Angle between the starting point and the end point
    // Usually atan2 is used with the parameters in the reverse order (atan2(y, x)).
    // The order here (x, y) is intentional, since otherwise horizontal drags would result in vertical movement
    // and vice versa
    // TODO Maybe hack to fix issue with backwards display? See getProjectedCoord
    const dist_phi = -math.atan2(f32, dist_x, dist_y);
    // const dist_phi = math.atan2(f32, dist_y, dist_x);

    // drag_distance is the angular distance between the starting location and the result location after a single drag
    // 2.35 is a magic number of degrees, picked because it results in what feels like an appropriate drag speed
    // Higher = move more with smaller cursor movements, and vice versa
    const drag_distance: f32 = math_utils.degToRad(canvas.settings.drag_speed);

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

pub fn getCoordForSkyCoord(sky_coord: SkyCoord, observer_timestamp: i64) Coord {
    const j2000_offset_millis: f64 = 949_428_000_000.0;
    const days_since_j2000 = (@intToFloat(f64, observer_timestamp) - j2000_offset_millis) / 86400000.0;
    var longitude = sky_coord.right_ascension - (100.46 + (0.985647 * days_since_j2000) + (15 * @intToFloat(f64, observer_timestamp)));
    longitude = math_utils.floatMod(longitude, 360);
    if (longitude < -180) {
        longitude += 360;
    } else if (longitude > 180) {
        longitude -= 360;
    }

    return Coord{
        .latitude = sky_coord.declination,
        .longitude = @floatCast(f32, longitude)
    };
}

pub fn getSkyCoordForCanvasPoint(canvas: *Canvas, point: Point, observer_location: Coord, observer_timestamp: i64) ?SkyCoord {
    if (!canvas.isInsideCircle(point)) return null;
    const raw_point = canvas.untranslatePoint(point);
    // Distance from raw_point to the center of the sky circle
    const s = math.sqrt(math.pow(f32, raw_point.x, 2.0) + math.pow(f32, raw_point.y, 2.0));
    const altitude = (math.pi * (1 - s)) / 2;

    const observer_lat_rad = math_utils.degToRad(observer_location.latitude);
    const sin_lat = math.sin(observer_lat_rad);
    const cos_lat = math.cos(observer_lat_rad);

    const declination = math_utils.boundedASin(((raw_point.y / s) * math.cos(altitude) * cos_lat) + (math.sin(altitude) * sin_lat)) catch |_| {
        log(.Error, "Error computing declination", .{});
        return null;
    };

    var hour_angle_rad = math_utils.boundedACos((math.sin(altitude) - (math.sin(declination) * sin_lat)) / (math.cos(declination) * cos_lat)) catch |_| {
        log(.Error, "Error computing hour angle. Declination was {d:.3}", .{declination});
        return null;
    };

    hour_angle_rad = if (raw_point.x < 0) -hour_angle_rad else hour_angle_rad;

    const hour_angle = math_utils.radToDeg(hour_angle_rad);
    const lst = getLocalSiderealTime(@intToFloat(f64, observer_timestamp), @floatCast(f64, observer_location.longitude));
    const right_ascension = math_utils.floatMod(lst - hour_angle, 360);

    return SkyCoord{
        .right_ascension = @floatCast(f32, right_ascension),
        .declination = math_utils.radToDeg(declination)
    };
}

pub fn getConstellationCentroid(constellation: Constellation) SkyCoord {
    var x: f32 = 0;
    var y: f32 = 0;
    var z: f32 = 0;

    for (constellation.boundaries) |b| {
        // convert to radians
        const ra_rad = b.right_ascension * (math.pi / 180.0);
        const dec_rad = b.declination * (math.pi / 180.0);

        x += math.cos(dec_rad) * math.cos(ra_rad);
        y += math.cos(dec_rad) * math.sin(ra_rad);
        z += math.sin(dec_rad);
    }

    x /= @intToFloat(f32, constellation.boundaries.len);
    y /= @intToFloat(f32, constellation.boundaries.len);
    z /= @intToFloat(f32, constellation.boundaries.len);

    const central_long = math.atan2(f32, y, x);
    const central_sqrt = math.sqrt(x * x + y * y);
    const central_lat = math.atan2(f32, z, central_sqrt);

    return SkyCoord{
        .right_ascension = central_long * (180.0 / math.pi),
        .declination = central_lat * (180.0 / math.pi)
    };
}

fn getLocalSiderealTime(current_timestamp: f64, longitude: f64) f64 {
    // The number of milliseconds between January 1st, 1970 and the J2000 epoch
    const j2000_offset_millis: f64 = 949_428_000_000.0;
    const days_since_j2000 = (current_timestamp - j2000_offset_millis) / 86_400_000.0;
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