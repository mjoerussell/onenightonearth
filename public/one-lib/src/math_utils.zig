const std = @import("std");
const math = std.math;
/// A radian-to-degree converter specialized for longitude values.
/// If the resulting degree value would be greater than 180 degrees,
/// 360 degrees will be subtracted - meaning that this function returns
/// values in a range of [-180, 180] degrees.
const rad_to_deg_constant = 180.0 / math.pi;
const deg_to_rad_constant = math.pi / 180.0;  

pub fn radToDegLong(radian: anytype) @TypeOf(radian) {
    const deg = radToDeg(radian);
    if (deg > 180.0) {
        return deg - 360.0;
    } else {
        return deg;
    }
}

/// A standard radian-to-degree conversion function.
pub fn radToDeg(radian: anytype) @TypeOf(radian) {
    return radian * rad_to_deg_constant;
}

/// A standard degree-to-radian conversion function.
pub fn degToRad(degree: anytype) @TypeOf(degree) {
    return degree * deg_to_rad_constant;
}

pub fn degToRadLong(degrees: anytype) @TypeOf(degree) {
    const norm_deg = if (degrees < 0) degrees + 360 else degrees;
    return degToRad(norm_deg);
}


pub const OperationError = error{NaN};

/// Safely perform acos on a value without worrying about the value being outside of the range [-1.0, 1.0]. The value
/// will be clamped to either end depending on whether it's too high or too low.
pub fn boundedACos(x: anytype) OperationError!@TypeOf(x) {
    const T = @TypeOf(x);
    const value = switch (T) {
        f32, f64 =>  math.acos(x),
        f128, comptime_float => return math.acos(@floatCast(f64, x)),
        else => @compileError("boundedACos not implemented for type " ++ @typeName(T)),
    };

    return if (std.math.isNan(value)) error.NaN else value;
}

pub fn boundedASin(x: anytype) OperationError!@TypeOf(x) {
    const T = @TypeOf(x);
    const value = switch (T) {
        f32, f64 => math.asin(x),
        f128, comptime_float => math.asin(@floatCast(f64, x)),
        else => @compileError("boundedACos not implemented for type " ++ @typeName(T)),
    };

    return if (std.math.isNan(value)) error.NaN else value;
}

fn FloatModResult(comptime input_type: type) type {
    return switch (@typeInfo(input_type)) {
        .ComptimeFloat => f128,
        .Float => input_type,
        else => @compileError("floatMod is not implemented for type " ++ @typeName(input_type))
    };
}

pub fn floatMod(num: anytype, denom: @TypeOf(num)) FloatModResult(@TypeOf(num)) {
    const T = @TypeOf(num);
    // comptime_float is not compatable with math.fabs, so cast to f128 before using
    const numerator = if (T == comptime_float) @floatCast(f128, num) else num;
    const denominator = if (T == comptime_float) @floatCast(f128, denom) else denom;

    const div = math.floor(math.absFloat(numerator / denominator));
    const whole_part = math.absFloat(denominator) * div;

    return if (num < 0) num + whole_part else num - whole_part;
}

test "degree to radian conversion" {
    const epsilon = 0.001;
    const degree = 45.0;
    const radian = degToRad(degree);
    expectWithinEpsilon(math.pi / 4.0, radian, epsilon);
}

test "radian to degree conversion" {
    const epsilon = 0.001;
    const degree = comptime radToDeg(math.pi / 4.0);
    expectWithinEpsilon(45.0, degree, epsilon);
}

test "custom float modulus" {
    const margin = 0.0001;
    expectEqual(1.0, comptime floatMod(4.0, 1.5));
    expectWithinMargin(1.3467, comptime floatMod(74.17405, 14.56547), margin);
    expectWithinMargin(1.3467, comptime floatMod(74.17405, -14.56547), margin);
    expectWithinMargin(-1.3467, comptime floatMod(-74.17405, -14.56547), margin);
    expectWithinMargin(-1.3467, comptime floatMod(-74.17405, 14.56547), margin);
}

test "longitude back and forth conversion - negative" {
    const epsilon = 0.001;
    const degLong = -75.0;
    const radLong = comptime degToRad(degLong);
    const backDegLong = comptime radToDegLong(radLong);
    expectWithinEpsilon(-degLong, -backDegLong, epsilon);

}