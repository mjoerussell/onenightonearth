const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Sphere = struct {

    vertices: []f32,
    normals: []f32,
    indices: []usize,

    pub fn init(allocator: *Allocator, radius: f32, num_sectors: usize, num_stacks: usize) !Sphere {
        var vert_list = ArrayList(f32).init(allocator);
        var norm_list = ArrayList(f32).init(allocator);
        var index_list = ArrayList(usize).init(allocator);

        const rad_inv = 1.0 / radius;
        const stack_step: f32 = math.pi / @intToFloat(f32, num_stacks);
        const sector_step: f32 = 2.0 * math.pi / @intToFloat(f32, num_sectors); 

        // Generate vertices & normals
        {
            var i: f32 = 0;
            while (i <= @intToFloat(f32, num_stacks)) : (i += 1) {
                // From pi/2 to -pi/2
                const stack_angle = (math.pi / 2.0) - (i * stack_step);

                const xy = radius * math.cos(stack_angle);
                const z = radius * math.sin(stack_angle);

                var j: f32 = 0;
                while (j <= @intToFloat(f32, num_sectors)) : (j += 1) {
                    // From 0 to 2pi
                    const sector_angle = j * sector_step;

                    const x = xy * math.cos(sector_angle);
                    const y = xy * math.sin(sector_angle);

                    try vert_list.appendSlice(&[_]f32{ x, y, z });
                    
                    const norm_x = x * rad_inv;
                    const norm_y = y * rad_inv;
                    const norm_z = z * rad_inv;

                    try norm_list.appendSlice(&[_]f32{ norm_x, norm_y, norm_z });
                }
            }
        }

        // Generate indices
        {
            var i: usize = 0;
            while (i < num_stacks) : (i += 1) {
                // The beginning of the current stack
                var k1: usize = i * (num_sectors + 1);
                // The beginning of the next stack
                var k2: usize = k1 + num_sectors + 1;

                var j: usize = 0;
                while (j < num_sectors) : (j += 1) {
                    if (i != 0) {
                        try index_list.appendSlice(&[_]usize{ k1, k2, k1 + 1 });
                    }

                    if (i != num_stacks - 1) {
                        try index_list.appendSlice(&[_]usize{ k1 + 1, k2, k2 + 1 });
                    }

                    k1 += 1;
                    k2 += 1;
                }
            }
        }

        return Sphere{
            .vertices = vert_list.toOwnedSlice(),
            .indices = index_list.toOwnedSlice(),
            .normals = norm_list.toOwnedSlice()
        };
    }

    pub fn deinit(self: *Sphere, allocator: *Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        allocator.free(self.normals);
    }

};