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

const fixed_point = @import("fixed_point.zig");
const FixedPoint = fixed_point.FixedPoint(i16, 12);

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

pub const Star = struct {
    right_ascension: f32,
    declination: f32,
    sin_declination: f32,
    cos_declination: f32,
    pixel: Pixel,

    pub fn fromExternStar(ext_star: ExternStar) Star {
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

};

pub const ExternStar = packed struct {
    right_ascension: i16,
    declination: i16,
    brightness: u8,
    spec_type: SpectralType,

    pub fn getColor(star: ExternStar) Pixel {
        var base_color = star.spec_type.getColor();
        base_color.a = star.brightness;

        return base_color;
    }
};

pub const Constellation = struct {
    /// Iterate over the boundaries two at a time. The iteration goes like this:
    ///
    /// Boundary List: `A - B - C - D`
    ///
    /// Iteration: `(A B) - (B C) - (C D) - (D A)`
    pub const BoundaryIter = struct {
        constellation: Constellation,
        boundary_index: usize = 0,

        pub fn next(iter: *BoundaryIter) ?[2]SkyCoord {
            if (iter.boundary_index >= iter.constellation.boundaries.len) {
                return null;
            }

            if (iter.boundary_index == iter.constellation.boundaries.len - 1) {
                const result = [2]SkyCoord{ iter.constellation.boundaries[iter.boundary_index], iter.constellation.boundaries[0] };
                iter.boundary_index += 1;
                return result; 
            }
            
            const result = [2]SkyCoord{ iter.constellation.boundaries[iter.boundary_index], iter.constellation.boundaries[iter.boundary_index + 1] };
            iter.boundary_index += 1;
            return result;
        }
    };
    
    asterism: []SkyCoord,
    boundaries: []SkyCoord,
    is_zodiac: bool,

    pub fn boundary_iter(self: Constellation) BoundaryIter {
        return .{ .constellation = self };
    }

    /// The centroid of a constellation is the coordinate that, when navigated to, will put the constellation
    /// in the center of the canvas. This point might be outside of the boundaries of the constellation if that
    /// constellation is irregularly shaped.
    pub fn centroid(constellation: Constellation) SkyCoord {
        var x: f32 = 0;
        var y: f32 = 0;
        var z: f32 = 0;

        for (constellation.boundaries) |b| {
            const ra_f32 = FixedPoint.toFloat(b.right_ascension);
            const dec_f32 = FixedPoint.toFloat(b.declination);
            x += math.cos(dec_f32) * math.cos(ra_f32);
            y += math.cos(dec_f32) * math.sin(ra_f32);
            z += math.sin(dec_f32);
        }

        x /= @intToFloat(f32, constellation.boundaries.len);
        y /= @intToFloat(f32, constellation.boundaries.len);
        z /= @intToFloat(f32, constellation.boundaries.len);

        const central_long = math.atan2(f32, y, x);
        const central_sqrt = math.sqrt(x * x + y * y);
        const central_lat = math.atan2(f32, z, central_sqrt);

        return SkyCoord{
            .right_ascension = FixedPoint.fromFloat(central_long),
            .declination = FixedPoint.fromFloat(central_lat)
        };
    }
};

// @todo It's possible that the reason for the contellation flickering is that the constellations at the end of the list
// aren't getting drawn before the next draw cycle starts. That could explain why they happen towards the middle of the screen,
// since the constellations are ordered in a roughly clockwise-by-longitude way. Needs more investigation though

/// A Great Circle is a circle that intersects the center of a sphere. The path along a great circle is the shortest path between
/// two points on the surface of a sphere.
pub fn GreatCircle(comptime num_waypoints: usize) type {
    return struct {
        const Self = @This();

        start: Coord = .{ .latitude = 0, .longitude = 0},
        end: Coord = .{ .latitude = 0, .longitude = 0},

        /// The angular distance between start and end. Measured in radians.
        distance: f32 = 0,

        /// The course angle is the angle at which the great circle path crosses the
        /// equator.
        course_angle: f32 = 0,

        /// waypooints are equidistant along the great circle path between start and end.
        waypoints: [num_waypoints]Coord = undefined,

        pub fn init(start: Coord, end: Coord) Self {
            var great_circle = Self{
                .start = start,
                .end = end,
            };

            if (great_circle.start.longitude > math.pi) {
                great_circle.start.longitude -= 2 * math.pi;
            }
            if (great_circle.end.longitude > math.pi) {
                great_circle.end.longitude -= 2 * math.pi;
            }

            great_circle.distance = blk: {
                const long_diff = great_circle.end.longitude - great_circle.start.longitude;
                const cos_d = math.sin(great_circle.start.latitude) * math.sin(great_circle.end.latitude) + math.cos(great_circle.start.latitude) * math.cos(great_circle.end.latitude) * math.cos(long_diff);
                break :blk math_utils.boundedACos(cos_d) catch 0;    
            };

            great_circle.course_angle = blk: {
                var cos_c = (math.sin(great_circle.end.latitude) - math.sin(great_circle.start.latitude) * math.cos(great_circle.distance)) / (math.cos(great_circle.start.latitude) * math.sin(great_circle.distance));
                break :blk math_utils.boundedACos(cos_c) catch 0;
            };

            const negative_dir: bool = great_circle.end.longitude < great_circle.start.longitude and great_circle.end.longitude > (great_circle.start.longitude - math.pi);

            const waypoint_inc: f32 = great_circle.distance / @intToFloat(f32, num_waypoints);
            
            for (great_circle.waypoints) |*waypoint, i| {
                const waypoint_dist = @intToFloat(f32, i + 1) * waypoint_inc;
                const lat = blk: {
                    const sin_lat_x = math.sin(great_circle.start.latitude) * math.cos(waypoint_dist) + math.cos(great_circle.start.latitude) * math.sin(waypoint_dist) * math.cos(great_circle.course_angle);
                    break :blk math_utils.boundedASin(sin_lat_x) catch 0;
                };
                const rel_long = blk: {
                    const cos_long_x = (math.cos(waypoint_dist) - math.sin(great_circle.start.latitude) * math.sin(lat)) / (math.cos(great_circle.start.latitude) * math.cos(lat));
                    break :blk math_utils.boundedACos(cos_long_x) catch 0;
                };

                const long = if (negative_dir) great_circle.start.longitude - rel_long else great_circle.start.longitude + rel_long;

                waypoint.* = Coord{ 
                    .latitude = lat, 
                    .longitude = long 
                };
            }

            return great_circle;
        }
    };
}

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

/// Draw a star on the canvas
pub fn projectStar(canvas: *Canvas, star: ExternStar, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32) void {
    const point = canvas.coordToPoint(
        SkyCoord{ .right_ascension = star.right_ascension, .declination = star.declination },
        local_sidereal_time,
        sin_latitude,
        cos_latitude,
        true
    ) orelse return;

    canvas.setPixelAt(point, star.getColor());
    if (canvas.isInsideCircle(point)) {
        canvas.setPixelAt(point, star.getColor());
    }
}

/// Draw the boundaries of a constellation.
pub fn projectConstellationGrid(canvas: *Canvas, constellation: Constellation, color: Pixel, line_width: u32, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32) void {
    var iter = constellation.boundary_iter();
    while (iter.next()) |bound| {
        const point_a = canvas.coordToPoint(bound[0], local_sidereal_time, sin_latitude, cos_latitude, false).?;
        const point_b = canvas.coordToPoint(bound[1], local_sidereal_time, sin_latitude, cos_latitude, false).?;

        if (!canvas.isInsideCircle(point_a) and !canvas.isInsideCircle(point_b)) {
            continue;
        }

        var line_index: u32 = 0;
        while (line_index < line_width) : (line_index += 1) {
            const start = Point{ .x = point_a.x + @intToFloat(f32, line_index), .y = point_a.y + @intToFloat(f32, line_index) };
            const end = Point{ .x = point_b.x + @intToFloat(f32, line_index), .y = point_b.y + @intToFloat(f32, line_index) };
            canvas.drawLine(Line{ .a = start, .b = end }, color);
        }
        
    }
}

/// Draw the asterism (pattern) of a constellation.
pub fn projectConstellationAsterism(canvas: *Canvas, constellation: Constellation, color: Pixel, line_width: u32, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32) void {
    var branch_index: usize = 0;
    while (branch_index < constellation.asterism.len - 1) : (branch_index += 2) {
        const point_a = canvas.coordToPoint(constellation.asterism[branch_index], local_sidereal_time, sin_latitude, cos_latitude, false) orelse continue;
        const point_b = canvas.coordToPoint(constellation.asterism[branch_index + 1], local_sidereal_time, sin_latitude, cos_latitude, false) orelse continue;

        if (!canvas.isInsideCircle(point_a) and !canvas.isInsideCircle(point_b)) {
            continue;
        }
        
        var line_index: u32 = 0;
        while (line_index < line_width) : (line_index += 1) {
            const start = Point{ .x = point_a.x + @intToFloat(f32, line_index), .y = point_a.y + @intToFloat(f32, line_index) };
            const end = Point{ .x = point_b.x + @intToFloat(f32, line_index), .y = point_b.y + @intToFloat(f32, line_index) };
            canvas.drawLine(Line{ .a = start, .b = end }, color);
        }
    }
}

/// Get the constellation that's currently at the point on the canvas.
pub fn getConstellationAtPoint(canvas: *Canvas, point: Point, constellations: []Constellation, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32) ?usize {
    if (!canvas.isInsideCircle(point)) return null;

    // Get a ray projected from the point to the right side of the canvas
    const point_ray_right = Line{ 
        .a = point, 
        .b = Point{ .x = @intToFloat(f32, canvas.settings.width), .y = point.y } 
    };
    // Get a ray projected from the point to the left side of the canvas
    const point_ray_left = Line{ 
        .a = point, 
        .b = Point{ .x = -@intToFloat(f32, canvas.settings.width), .y = point.y } 
    };

    for (constellations) |c, constellation_index| {
        if (canvas.settings.zodiac_only and !c.is_zodiac) continue;
        
        var num_intersections_right: u32 = 0;
        var num_intersections_left: u32 = 0;

        // Loop over all of the boundaries and count how many times both rays intersect with the boundary line
        // If they intersect inside the canvas circle, then add that to the left or right intersection counter
        var iter = c.boundary_iter();
        while (iter.next()) |bound| {
            const b_a = canvas.coordToPoint(bound[0], local_sidereal_time, sin_latitude, cos_latitude, false) orelse continue;
            const b_b = canvas.coordToPoint(bound[1], local_sidereal_time, sin_latitude, cos_latitude, false) orelse continue;

            const bound_line = Line{ .a = b_a, .b = b_b };
            if (point_ray_right.segmentIntersection(bound_line)) |_| {
                num_intersections_right += 1;
            }

            if (point_ray_left.segmentIntersection(bound_line)) |_| {
                num_intersections_left += 1;
            }
        }
        // If there are an odd number of intersections on the left and right side of the point, then the point
        // is inside the shape
        if (num_intersections_left % 2 == 1 and num_intersections_right % 2 == 1) {
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

