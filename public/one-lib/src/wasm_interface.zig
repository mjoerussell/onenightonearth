const std = @import("std");
const math = std.math;
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;

const log = @import("./log.zig").log;

const render = @import("./render.zig");
const Canvas = render.Canvas;
const Pixel = render.Pixel;

const math_utils = @import("./math_utils.zig");
const Point = math_utils.Point;

const star_math = @import("./star_math.zig");
const Star = star_math.Star;
const Constellation = star_math.Constellation;
const SkyCoord = star_math.SkyCoord;
const Coord = star_math.Coord;

const matrix = @import("./matrix.zig");
const Mat2D = matrix.Mat2D;
const Mat3D = matrix.Mat3D;
const Mat3f = matrix.Mat3f;
const Mat4f = matrix.Mat4f;
const Vec3f = matrix.Vec3f;

const Sphere = @import("./sphere.zig").Sphere;

const allocator = std.heap.page_allocator;
var canvas: Canvas = undefined;
var stars: []Star = undefined;

var star_sphere: Sphere = undefined;

var constellations: []Constellation = undefined;

const ExternCanvasSettings = packed struct {
    width: u32,
    height: u32,
    background_radius: f32,
    zoom_factor: f32,
    drag_speed: f32,
    fov: f32,
    draw_north_up: u8,
    draw_constellation_grid: u8,
    draw_asterisms: u8,

    fn getCanvasSettings(self: ExternCanvasSettings) Canvas.Settings {
        return Canvas.Settings{
            .width = self.width,
            .height = self.height,
            .background_radius = self.background_radius,
            .zoom_factor = self.zoom_factor,
            .drag_speed = self.drag_speed,
            .fov = self.fov,
            .draw_north_up = self.draw_north_up == 1,
            .draw_constellation_grid = self.draw_constellation_grid == 1,
            .draw_asterisms = self.draw_asterisms == 1
        };
    }
};

pub export fn initializeStars(star_data: [*]Star, star_len: u32) void {
    stars = star_data[0..star_len];
}

pub export fn initializeCanvas(settings: *ExternCanvasSettings) void {
    canvas = Canvas.init(allocator, settings.getCanvasSettings()) catch |err| switch (err) {
        error.OutOfMemory => {
            const num_pixels = canvas.settings.width * canvas.settings.height;
            log(.Error, "Ran out of memory during canvas intialization (needed {} kB for {} pixels)", .{(num_pixels * @sizeOf(Pixel)) / 1000, num_pixels});
            unreachable;
        }
    };

    star_sphere = Sphere.init(allocator, 1, 18, 36) catch unreachable;
    // star_sphere = Sphere.init(allocator, 1, 9, 9) catch unreachable;
}

pub export fn initializeConstellations(constellation_grid_data: [*][*]SkyCoord, constellation_asterism_data: [*][*]SkyCoord, grid_coord_lens: [*]u32, asterism_coord_lens: [*]u32, num_constellations: u32) void {
    constellations = allocator.alloc(Constellation, num_constellations) catch unreachable;

    defer allocator.free(grid_coord_lens[0..num_constellations]);
    defer allocator.free(asterism_coord_lens[0..num_constellations]);
    for (constellations) |*c, i| {
        c.* = Constellation{
            .asterism = constellation_asterism_data[i][0..asterism_coord_lens[i]],
            .boundaries = constellation_grid_data[i][0..grid_coord_lens[i]]
        };
    }

}

pub export fn updateCanvasSettings(settings: *ExternCanvasSettings) void {
    canvas.settings = settings.getCanvasSettings();
    allocator.destroy(settings);
}

pub export fn getImageData(size_in_bytes: *u32) [*]Pixel {
    size_in_bytes.* = @intCast(u32, canvas.data.len * @sizeOf(Pixel));
    return canvas.data.ptr;
}

pub export fn resetImageData() void {
    for (canvas.data) |*p, i| {
        p.* = Pixel{};
    }   
}

pub export fn getViewProjectionMatrix() *[16]f32 {
    // var camera_matrix = Mat3D.getXRotation(0);
    // camera_matrix = Mat3D.getTranslation(0, canvas.settings.background_radius / 2, (4 * canvas.settings.background_radius) / canvas.settings.zoom_factor).mult(camera_matrix);
    const z_bound = -0.85 * canvas.settings.background_radius;
    var z_pos = (5.15 * canvas.settings.background_radius) - (canvas.settings.zoom_factor * canvas.settings.background_radius);
    if (z_pos < z_bound) {
        z_pos = z_bound;
    }
    var camera_matrix = Mat3D.getXRotation(math.pi / 2.0);
    camera_matrix = Mat3D.getTranslation(0, 0, z_pos).mult(camera_matrix);
    if (!canvas.settings.draw_north_up) {
        camera_matrix = Mat3D.getZRotation(math.pi).mult(camera_matrix);
    }

    const view_matrix = camera_matrix.inverse() catch |err| {
        log(.Error, "Invalid camera position", .{});
        unreachable;
    };
    const view_projection_matrix = view_matrix.mult(canvas.getProjectionMatrix());

    const result_ptr = allocator.create([16]f32) catch unreachable;
    result_ptr.* = view_projection_matrix.flatten();
    return result_ptr;
}

pub export fn projectStars(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64, num_stars: *usize) *[2][*]f32 {
    const current_coord = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };

    var star_matrices = std.ArrayList(f32).init(allocator);
    var star_colors = std.ArrayList(f32).init(allocator);

    for (stars) |star| {
        const m = star_math.projectStar(&canvas, star, current_coord, observer_timestamp, true);
        if (m) |star_matrix| {
            // TODO: Better error handling here (used to have logs + return immediately)
            star_matrices.appendSlice(star_matrix.flatten()[0..]) catch unreachable;
            const star_color = star.spec_type.getColor();
            star_colors.appendSlice(&[4]f32{ @intToFloat(f32, star_color.r) / 255.0, @intToFloat(f32, star_color.g) / 255.0, @intToFloat(f32, star_color.b) / 255.0, @intToFloat(f32, star_color.a) / 255.0 }) catch |err| {
                log(.Error, "{} error while setting star color", .{@errorName(err)});
            };
        }
    }

    const mats = star_matrices.toOwnedSlice();
    const colors = star_colors.toOwnedSlice();

    const result_ptr = allocator.create([2][*]f32) catch unreachable;

    result_ptr[0] = mats.ptr;
    result_ptr[1] = colors.ptr;

    num_stars.* = mats.len / 16;

    return result_ptr;
}

pub export fn projectConstellationGrids(observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) void {
    // const current_coord = Coord{
    //     .latitude = observer_latitude,
    //     .longitude = observer_longitude
    // };

    // if (canvas.settings.draw_constellation_grid or canvas.settings.draw_asterisms) {
    //     for (constellations) |constellation| {
    //         if (canvas.settings.draw_constellation_grid) {
    //             star_math.projectConstellationGrid(&canvas, constellation, Pixel.rgba(255, 245, 194, 155), 1, current_coord, observer_timestamp);
    //         }
    //         if (canvas.settings.draw_asterisms) {
    //             star_math.projectConstellationAsterism(&canvas, constellation, Pixel.rgba(255, 245, 194, 155), 1, current_coord, observer_timestamp);
    //         }
    //     }
    // }
}

pub export fn getConstellationAtPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) isize {
    // const observer_coord = Coord{
    //     .latitude = observer_latitude,
    //     .longitude = observer_longitude
    // };
    // defer allocator.destroy(point);
    // const index = star_math.getConstellationAtPoint(&canvas, point.*, constellations, observer_coord, observer_timestamp);
    // if (index) |i| {
    //     if (canvas.settings.draw_constellation_grid) {
    //         star_math.projectConstellationGrid(&canvas, constellations[i], Pixel.rgb(255, 255, 255), 2, observer_coord, observer_timestamp);
    //     }
    //     if (canvas.settings.draw_asterisms) {
    //         star_math.projectConstellationAsterism(&canvas, constellations[i], Pixel.rgb(255, 255, 255), 2, observer_coord, observer_timestamp);
    //     }
    //     return @intCast(isize, i);
    // } else return -1;
    return 0;
}

pub export fn dragAndMove(drag_start_x: f32, drag_start_y: f32, drag_end_x: f32, drag_end_y: f32) *Coord {
    const coord = star_math.dragAndMove(&canvas, drag_start_x, drag_start_y, drag_end_x, drag_end_y);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn findWaypoints(f: *const Coord, t: *const Coord, num_waypoints: *u32) [*]Coord {
    defer allocator.destroy(f);
    defer allocator.destroy(t);

    const waypoints = star_math.findWaypoints(allocator, f.*, t.*);
    num_waypoints.* = @intCast(u32, waypoints.len);
    return waypoints.ptr;
}

pub export fn getCoordForSkyCoord(sky_coord: *SkyCoord, observer_timestamp: i64) *Coord {
    defer allocator.destroy(sky_coord);
    const coord = star_math.getCoordForSkyCoord(sky_coord.*, observer_timestamp);
    const coord_ptr = allocator.create(Coord) catch unreachable;
    coord_ptr.* = coord;
    return coord_ptr;
}

pub export fn getSkyCoordForCanvasPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) ?*SkyCoord {
    defer allocator.destroy(point);
    const observer_location = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };
    const sky_coord = star_math.getSkyCoordForCanvasPoint(&canvas, point.*, observer_location, observer_timestamp);
    if (sky_coord) |sk| {
        const sky_coord_ptr = allocator.create(SkyCoord) catch unreachable;
        sky_coord_ptr.* = sk;
        return sky_coord_ptr;
    } else {
        return null;
    }
}

pub export fn getCoordForCanvasPoint(point: *Point, observer_latitude: f32, observer_longitude: f32, observer_timestamp: i64) ?*Coord {
    defer allocator.destroy(point);
    const observer_location = Coord{
        .latitude = observer_latitude,
        .longitude = observer_longitude
    };
    const sky_coord = star_math.getSkyCoordForCanvasPoint(&canvas, point.*, observer_location, observer_timestamp);
    if (sky_coord) |sk| {
        const coord = star_math.getCoordForSkyCoord(sk, observer_timestamp);
        const coord_ptr = allocator.create(Coord) catch unreachable;
        coord_ptr.* = coord;
        return coord_ptr;
    } else {
        return null;
    }
}

pub export fn getConstellationCentroid(constellation_index: usize) ?*SkyCoord {
    // if (constellation_index > constellations.len) return null;

    // const coord_ptr = allocator.create(SkyCoord) catch unreachable;
    // coord_ptr.* = star_math.getConstellationCentroid(constellations[constellation_index]);
    // return coord_ptr;
    return null;
}

pub export fn getProjectionMatrix2d(width: f32, height: f32) *Mat3f {
    const m = Mat2D.getProjection(width, height);
    const m_ptr = allocator.create(Mat3f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getProjectionMatrix3d(width: f32, height: f32, depth: f32) *Mat4f {
    const m = Mat3D.getProjection(width, height, depth);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getRotationMatrix2d(radians: f32) *Mat3f {
    const m = Mat2D.getRotation(radians);
    const m_ptr = allocator.create(Mat3f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getXRotationMatrix3d(radians: f32) *Mat4f {
    const m = Mat3D.getXRotation(radians);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getYRotationMatrix3d(radians: f32) *Mat4f {
    const m = Mat3D.getYRotation(radians);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getZRotationMatrix3d(radians: f32) *Mat4f {
    const m = Mat3D.getZRotation(radians);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getTranslationMatrix2d(tx: f32, ty: f32) *Mat3f {
    const m = Mat2D.getTranslation(tx, ty);
    const m_ptr = allocator.create(Mat3f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getTranslationMatrix3d(tx: f32, ty: f32, tz: f32) *Mat4f {
    const m = Mat3D.getTranslation(tx, ty, tz);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getScalingMatrix2d(sx: f32, sy: f32) *Mat3f {
    const m = Mat2D.getScaling(sx, sy);
    const m_ptr = allocator.create(Mat3f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getScalingMatrix3d(sx: f32, sy: f32, sz: f32) *Mat4f {
    const m = Mat3D.getScaling(sx, sy, sz);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getOrthographicMatrix3d(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) *Mat4f {
    const m = Mat3D.getOrthographic(left, right, bottom, top, near, far);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn getPerspectiveMatrix3d(fov: f32, aspect_ratio: f32, near: f32, far: f32) *Mat4f {
    const m = Mat3D.getPerspective(fov, aspect_ratio, near, far);
    const m_ptr = allocator.create(Mat4f) catch unreachable;
    m_ptr.* = m;
    return m_ptr;
}

pub export fn matrixMult2d(a: *Mat3f, b: *Mat3f) *Mat3f {
    const result = a.mult(b.*);
    const result_ptr = allocator.create(Mat3f) catch unreachable;
    result_ptr.* = result;
    return result_ptr;
}

pub export fn matrixMult3d(a: *Mat4f, b: *Mat4f) *Mat4f {
    const result = a.mult(b.*);
    const result_ptr = allocator.create(Mat4f) catch unreachable;
    result_ptr.* = result;
    return result_ptr;
}

pub export fn readMatrix2d(m: *Mat3f) *[9]f32 {
    var result: [9]f32 = m.flatten();
    const result_ptr = allocator.create([9]f32) catch unreachable;
    result_ptr.* = result;
    return result_ptr;
}

pub export fn readMatrix3d(m: *Mat4f) *[16]f32 {
    var result: [16]f32 = m.flatten();
    const result_ptr = allocator.create([16]f32) catch unreachable;
    result_ptr.* = result;
    return result_ptr;
}

pub export fn freeMatrix2d(m: *Mat3f) void {
    allocator.destroy(m);
}

pub export fn freeMatrix3d(m: *Mat4f) void {
    allocator.destroy(m);
}

pub export fn getSphereVertices(result_len: *usize) [*]f32 {
    result_len.* = star_sphere.vertices.len;
    return star_sphere.vertices.ptr;
}

pub export fn getSphereIndices(result_len: *usize) [*]usize {
    result_len.* = star_sphere.indices.len;
    return star_sphere.indices.ptr;
}

pub export fn getSphereNormals(result_len: *usize) [*]f32 {
    result_len.* = star_sphere.normals.len;
    return star_sphere.normals.ptr;
}

pub export fn _wasm_alloc(byte_len: u32) ?[*]u8 {
    const buffer = allocator.alloc(u8, byte_len) catch |err| return null;
    return buffer.ptr;
}

pub export fn _wasm_free(items: [*]u8, byte_len: u32) void {
    const bounded_items = items[0..byte_len];
    allocator.free(bounded_items);

    log(.Debug, "Freed {} bytes", .{byte_len});
}
