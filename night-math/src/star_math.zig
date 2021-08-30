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

pub const Coord = packed struct {
    latitude: f32,
    longitude: f32,
};

pub const SkyCoord = packed struct {
    right_ascension: f32,
    declination: f32
};

pub const ObserverPosition = struct {
    latitude: f32,
    longitude: f32,
    timestamp: i64,

    pub fn localSiderealTime(pos: ObserverPosition) f64 {
        const j2000_offset_millis = 949_428_000_000;
        const days_since_j2000 = @intToFloat(f64, pos.timestamp - j2000_offset_millis) / 86_400_000.0;
        return 100.46 + (0.985647 * days_since_j2000) + @floatCast(f64, pos.longitude) + @intToFloat(f64, 15 * pos.timestamp);
    }

};

pub const Star = packed struct {
    right_ascension: f32,
    declination: f32,
    brightness: f32,
    spec_type: SpectralType,

    pub fn getColor(star: Star) Pixel {
        var base_color = star.spec_type.getColor();
        base_color.a = blk: {
            const brightness = star.brightness + 0.15;
            break :blk if (brightness >= 1.0)
                255
            else if (brightness <= 0) 
                0
            else @floatToInt(u8, brightness * 255.0);
        };

        return base_color;
    }
};

pub const Constellation = struct {
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

    pub fn centroid(constellation: Constellation) SkyCoord {
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
};

// @todo It's possible that the reason for the contellation flickering is that the constellations at the end of the list
// aren't getting drawn before the next draw cycle starts. That could explain why they happen towards the middle of the screen,
// since the constellations are ordered in a roughly clockwise-by-longitude way. Needs more investigation though

pub fn GreatCircle(comptime num_waypoints: usize) type {
    return struct {
        const Self = @This();

        start: Coord,
        end: Coord,
        distance: f32,
        course_angle: f32,

        waypoints: [num_waypoints]Coord = undefined,

        pub fn init(start: Coord, end: Coord) Self {
            const start_radians = Coord{
                .latitude = math_utils.degToRad(start.latitude),
                .longitude = math_utils.degToRadLong(start.longitude)
            };
            const end_radians = Coord{
                .latitude = math_utils.degToRad(end.latitude),
                .longitude = math_utils.degToRadLong(end.longitude)
            };

            const distance = blk: {
                const long_diff = end_radians.longitude - start_radians.longitude;
                const cos_d = math.sin(start_radians.latitude) * math.sin(end_radians.latitude) + math.cos(start_radians.latitude) * math.cos(end_radians.latitude) * math.cos(long_diff);
                break :blk math_utils.boundedACos(cos_d) catch 0;    
            };

            const course_angle = blk: {
                var cos_c = (math.sin(end_radians.latitude) - math.sin(start_radians.latitude) * math.cos(distance)) / (math.cos(start_radians.latitude) * math.sin(distance));
                break :blk math_utils.boundedACos(cos_c) catch 0;
            };

            var great_circle = Self{ 
                .start = start_radians,
                .end = end_radians,
                .distance = distance, 
                .course_angle = course_angle,
            };

            const negative_dir = great_circle.end.longitude < great_circle.start.longitude and great_circle.end.longitude > (great_circle.start.longitude - math.pi);

            const waypoint_inc: f32 = great_circle.distance / @intToFloat(f32, num_waypoints);
            var waypoints: [num_waypoints]Coord = undefined;
            
            for (waypoints) |*waypoint, i| {
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
                    .latitude = math_utils.radToDeg(lat), 
                    .longitude = math_utils.radToDegLong(long) 
                };
            }

            great_circle.waypoints = waypoints;

            return great_circle;
        }
    };
}

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

pub fn projectStar(canvas: *Canvas, star: Star, observer_pos: ObserverPosition) void {
    const point = canvas.projectToCanvas(
        SkyCoord{ .right_ascension = star.right_ascension, .declination = star.declination }, 
        observer_pos,
        true
    ) orelse return;

    if (canvas.isInsideCircle(point)) {
        // var base_color = star.spec_type.getColor();
        // base_color.a = getAlpha(star.brightness + 0.15);
        canvas.setPixelAt(point, star.getColor());
    }
}

pub fn projectConstellationGrid(canvas: *Canvas, constellation: Constellation, color: Pixel, line_width: u32, observer_pos: ObserverPosition) void {
    var iter = constellation.boundary_iter();
    while (iter.next()) |bound| {
        const point_a = canvas.projectToCanvas(bound[0], observer_pos, false) orelse continue;
        const point_b = canvas.projectToCanvas(bound[1], observer_pos, false) orelse continue;
        
        canvas.drawLine(Line{ .a = point_a, .b = point_b }, color, line_width);
    }
}

pub fn projectConstellationAsterism(canvas: *Canvas, constellation: Constellation, color: Pixel, line_width: u32, observer_pos: ObserverPosition) void {
    var branch_index: usize = 0;
    while (branch_index < constellation.asterism.len - 1) : (branch_index += 2) {
        const point_a = canvas.projectToCanvas(constellation.asterism[branch_index], observer_pos, false) orelse continue;
        const point_b = canvas.projectToCanvas(constellation.asterism[branch_index + 1], observer_pos, false) orelse continue;
        
        canvas.drawLine(Line{ .a = point_a, .b = point_b }, color, line_width);
    }
}

pub fn drawSkyGrid(canvas: Canvas, observer_pos: ObserverPosition) void {
    const grid_color = Pixel.rgba(91, 101, 117, 180);
    const grid_zero_color = Pixel.rgba(176, 98, 65, 225);
    var base_right_ascension: f32 = 0;

    while (base_right_ascension < 360) : (base_right_ascension += 15) {
        var declination: f32 = -90;
        while (declination <= 90) : (declination += 0.1) {
            const point = canvas.projectToCanvas(.{ .right_ascension = base_right_ascension, .declination = declination }, observer_pos, true);
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
            const point = canvas.projectToCanvas(.{ .right_ascension = right_ascension, .declination = base_declination }, observer_pos, true);
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

pub fn getConstellationAtPoint(canvas: *Canvas, point: Point, constellations: []Constellation, observer_pos: ObserverPosition) ?usize {
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
        
        // var b_index: usize = 0;
        var num_intersections_right: u32 = 0;
        var num_intersections_left: u32 = 0;

        // Loop over all of the boundaries and count how many times both rays intersect with the boundary line
        // If they intersect inside the canvas circle, then add that to the left or right intersection counter
        var iter = c.boundary_iter();
        while (iter.next()) |bound| {
            const b_a = canvas.projectToCanvas(bound[0], observer_pos, false) orelse continue;
            const b_b = canvas.projectToCanvas(bound[1], observer_pos, false) orelse continue;

            const bound_line = Line{ .a = b_a, .b = b_b };
            if (point_ray_right.segmentIntersection(bound_line)) |inter_point| {
                if (canvas.isInsideCircle(inter_point)) {
                    num_intersections_right += 1;
                }
            }

            if (point_ray_left.segmentIntersection(bound_line)) |inter_point| {
                if (canvas.isInsideCircle(inter_point)) {
                    num_intersections_left += 1;
                }
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
    const drag_distance: f32 = math_utils.degToRad(drag_speed);

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
    const j2000_offset_millis = 949_428_000_000;
    const days_since_j2000 = @intToFloat(f64, observer_timestamp - j2000_offset_millis) / 86400000.0;
    var longitude = sky_coord.right_ascension - (100.46 + (0.985647 * days_since_j2000) + @intToFloat(f64, 15 * observer_timestamp));
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

pub fn getSkyCoordForCanvasPoint(canvas: *Canvas, point: Point, observer_pos: ObserverPosition) ?SkyCoord {
    if (!canvas.isInsideCircle(point)) return null;
    const raw_point = canvas.untranslatePoint(point);
    // Distance from raw_point to the center of the sky circle
    const s = math.sqrt(math.pow(f32, raw_point.x, 2.0) + math.pow(f32, raw_point.y, 2.0));
    const altitude = (math.pi * (1 - s)) / 2;

    const observer_lat_rad = math_utils.degToRad(observer_pos.latitude);
    const sin_lat = math.sin(observer_lat_rad);
    const cos_lat = math.cos(observer_lat_rad);

    const declination = math_utils.boundedASin(((raw_point.y / s) * math.cos(altitude) * cos_lat) + (math.sin(altitude) * sin_lat)) catch {
        log(.Error, "Error computing declination", .{});
        return null;
    };

    var hour_angle_rad = math_utils.boundedACos((math.sin(altitude) - (math.sin(declination) * sin_lat)) / (math.cos(declination) * cos_lat)) catch {
        log(.Error, "Error computing hour angle. Declination was {d:.3}", .{declination});
        return null;
    };

    hour_angle_rad = if (raw_point.x < 0) -hour_angle_rad else hour_angle_rad;

    const hour_angle = math_utils.radToDeg(hour_angle_rad);
    const lst = observer_pos.localSiderealTime();
    const right_ascension = math_utils.floatMod(lst - hour_angle, 360);

    return SkyCoord{
        .right_ascension = @floatCast(f32, right_ascension),
        .declination = math_utils.radToDeg(declination)
    };
}