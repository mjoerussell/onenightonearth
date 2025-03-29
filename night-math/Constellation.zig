const std = @import("std");
const math = std.math;

const FixedPoint = @import("fixed_point.zig").DefaultFixedPoint;

const SkyCoord = @import("SkyCoord.zig");

const Canvas = @import("Canvas.zig");
const math_utils = @import("math_utils.zig");
const Line = math_utils.Line;
const Point = math_utils.Point;

const Constellation = @This();

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
        const ra_f32 = b.right_ascension;
        const dec_f32 = b.declination;
        x += math.cos(dec_f32) * math.cos(ra_f32);
        y += math.cos(dec_f32) * math.sin(ra_f32);
        z += math.sin(dec_f32);
    }

    x /= @as(f32, @floatFromInt(constellation.boundaries.len));
    y /= @as(f32, @floatFromInt(constellation.boundaries.len));
    z /= @as(f32, @floatFromInt(constellation.boundaries.len));

    const central_long = math.atan2(y, x);
    const central_sqrt = math.sqrt(x * x + y * y);
    const central_lat = math.atan2(z, central_sqrt);

    return SkyCoord{
        .right_ascension = central_long,
        .declination = central_lat,
    };
}

pub fn isPointInside(constellation: Constellation, canvas: Canvas, point: Point, local_sidereal_time: f32, sin_latitude: f32, cos_latitude: f32) bool {
    var num_intersections_right: u32 = 0;
    var num_intersections_left: u32 = 0;

    // Get a ray projected from the point to the right side of the canvas
    const point_ray_right = Line{ .a = point, .b = Point{ .x = @as(f32, @floatFromInt(canvas.settings.width)), .y = point.y } };
    // Get a ray projected from the point to the left side of the canvas
    const point_ray_left = Line{ .a = point, .b = Point{ .x = -@as(f32, @floatFromInt(canvas.settings.width)), .y = point.y } };

    // Loop over all of the boundaries and count how many times both rays intersect with the boundary line
    // If they intersect inside the canvas circle, then add that to the left or right intersection counter
    var iter = constellation.boundary_iter();
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
    return num_intersections_left % 2 == 1 and num_intersections_right % 2 == 1;
}
