const std = @import("std");

pub fn FixedPoint(comptime Int: type, comptime fractional_bits: u8) type {
    return packed struct {
        const Self = @This();

        pub inline fn fromFloat(float_value: f32) Int {
            return @as(Int, @intFromFloat(float_value * (1 << fractional_bits)));
        }

        pub inline fn toFloat(fixed: Int) f32 {
            return @as(f32, @floatFromInt(fixed)) / @as(f32, @floatFromInt(@as(Int, 1) << fractional_bits));
        }
    };
}
