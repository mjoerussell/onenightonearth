const std = @import("std");

pub const DefaultFixedPoint = FixedPoint(i16, 12);

pub fn FixedPoint(comptime Int: type, comptime fractional_bits: u8) type {
    if (!std.meta.trait.isIntegral(Int)) @compileError("FixedPoint requires an integer type as the target conversion");

    return packed struct {
        const Self = @This();

        pub inline fn fromFloat(float_value: f32) Int {
            return @floatToInt(Int, float_value * (1 << fractional_bits));
        }

        pub inline fn toFloat(fixed: Int) f32 {
            return @intToFloat(f32, fixed) / @intToFloat(f32, @as(Int, 1) << fractional_bits);
        }
    };
}