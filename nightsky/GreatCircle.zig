const std = @import("std");
const math = std.math;

const Coord = @import("star_math.zig").Coord;
const math_utils = @import("math_utils.zig");

const GreatCircle = @This();

const WaypointIterator = struct {
    start: Coord,
    num_waypoints: usize,
    waypoint_inc: f32,
    course_angle: f32,
    negative_dir: bool,
    current_waypoint: usize = 0,

    fn init(great_circle: GreatCircle, num_waypoints: usize) WaypointIterator {
        return WaypointIterator{
            .start = great_circle.start,
            .num_waypoints = num_waypoints,
            .waypoint_inc = great_circle.distance / @as(f32, @floatFromInt(num_waypoints)),
            .course_angle = great_circle.course_angle,
            .negative_dir = great_circle.end.longitude < great_circle.start.longitude and great_circle.end.longitude > (great_circle.start.longitude - math.pi),
        };
    }

    pub fn next(iter: *WaypointIterator) ?Coord {
        if (iter.current_waypoint >= iter.num_waypoints) return null;
        defer iter.current_waypoint += 1;

        const waypoint_dist = @as(f32, @floatFromInt(iter.current_waypoint + 1)) * iter.waypoint_inc;

        const sin_start_latitude = math.sin(iter.start.latitude);
        const cos_start_latitude = math.cos(iter.start.latitude);

        const sin_waypoint_latitude = sin_start_latitude * math.cos(waypoint_dist) + cos_start_latitude * math.sin(waypoint_dist) * math.cos(iter.course_angle);
        const waypoint_latitude = math_utils.boundedASin(sin_waypoint_latitude) catch 0;

        const rel_long = blk: {
            const cos_long_x = (math.cos(waypoint_dist) - sin_start_latitude * sin_waypoint_latitude) / (cos_start_latitude * math.cos(waypoint_latitude));
            break :blk math_utils.boundedACos(cos_long_x) catch 0;
        };

        const waypoint_longitude = if (iter.negative_dir) iter.start.longitude - rel_long else iter.start.longitude + rel_long;

        return Coord{
            .latitude = waypoint_latitude,
            .longitude = waypoint_longitude,
        };
    }
};

start: Coord = .{ .latitude = 0, .longitude = 0 },
end: Coord = .{ .latitude = 0, .longitude = 0 },

/// The angular distance between start and end. Measured in radians.
distance: f32 = 0,

/// The course angle is the angle at which the great circle path crosses the
/// equator.
course_angle: f32 = 0,

pub fn init(start: Coord, end: Coord) GreatCircle {
    var great_circle = GreatCircle{
        .start = start,
        .end = end,
    };

    if (great_circle.start.longitude > math.pi) {
        great_circle.start.longitude -= 2 * math.pi;
    }
    if (great_circle.end.longitude > math.pi) {
        great_circle.end.longitude -= 2 * math.pi;
    }

    const sin_start_latitude = math.sin(great_circle.start.latitude);
    const cos_start_latitude = math.cos(great_circle.start.latitude);
    const sin_end_latitude = math.sin(great_circle.end.latitude);
    const cos_end_latitude = math.cos(great_circle.end.latitude);

    const long_diff = great_circle.end.longitude - great_circle.start.longitude;
    const cos_d = sin_start_latitude * sin_end_latitude + cos_start_latitude * cos_end_latitude * math.cos(long_diff);
    great_circle.distance = math_utils.boundedACos(cos_d) catch 0;

    const cos_c = (sin_end_latitude - sin_start_latitude * math.cos(great_circle.distance)) / (cos_start_latitude * math.sin(great_circle.distance));
    great_circle.course_angle = math_utils.boundedACos(cos_c) catch 0;

    return great_circle;
}

pub fn getWaypoints(great_circle: GreatCircle, num_waypoints: usize) WaypointIterator {
    return WaypointIterator.init(great_circle, num_waypoints);
}
