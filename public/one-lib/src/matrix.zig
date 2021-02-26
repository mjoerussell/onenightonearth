const std = @import("std");
const math = std.math;
const floatEq = @import("./math_utils.zig").floatEq;

pub const Mat3f = Matrix(f32, 3, 3);
pub const Mat4f = Matrix(f32, 4, 4);

pub const Vec2f = Vector(f32, 2);
pub const Vec3f = Vector(f32, 3);
pub const Vec4f = Vector(f32, 4);

pub const MatrixType2D = packed enum(u8) {
    Projection,
    Translation,
    Rotation,
    Scaling,
};

pub const Mat2D = struct {
    pub fn getTranslation(tx: f32, ty: f32) Mat3f {
        return Mat3f.init(.{
            .{ 1, 0, 0 },
            .{ 0, 1, 0 },
            .{ tx, ty, 1 },
        });
    }
    
    pub fn getRotation(radians: f32) Mat3f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat3f.init(.{
            .{ c, -s, 0 },
            .{ s,  c, 0 },
            .{ 0,  0, 1 },
        });
    }

    pub fn getScaling(sx: f32, sy: f32) Mat3f {
        return Mat3f.init(.{
            .{ sx, 0, 0 },
            .{ 0, sy, 0 },
            .{ 0, 0, 1 },
        });
    }

    pub fn getProjection(width: f32, height: f32) Mat3f {
        return Mat3f.init(.{
            .{ 2 / width, 0, 0 },
            .{ 0, -2 / height, 0 },
            .{ -1, 1, 1 }
        });
    }

};

pub const Mat3D = struct {
    pub fn getTranslation(tx: f32, ty: f32, tz: f32) Mat4f {
        return Mat4f.init(.{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ tx, ty, tz, 1 },
        });
    }

    pub fn getXRotation(radians: f32) Mat4f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat4f.init(.{
            .{ 1, 0, 0, 0 },
            .{ 0, c, s, 0 },
            .{ 0, -s, c, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    pub fn getYRotation(radians: f32) Mat4f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat4f.init(.{
            .{ c, 0, -s, 0 },
            .{ 0, 1, 0, 0 },
            .{ s, 0, c, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    pub fn getZRotation(radians: f32) Mat4f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat4f.init(.{
            .{ c, s, 0, 0 },
            .{ -s, c, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    pub fn getScaling(sx: f32, sy: f32, sz: f32) Mat4f {
        return Mat4f.init(.{
            .{ sx, 0, 0, 0 },
            .{ 0, sy, 0, 0 },
            .{ 0, 0, sz, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    pub fn getProjection(width: f32, height: f32, depth: f32) Mat4f {
        return Mat4f.init(.{
            .{ 2 / width, 0, 0, 0 },
            .{ 0, -2 / height, 0, 0 },
            .{ 0, 0, 2 / depth, 0 },
            .{ -1, 1, 0, 1 },
        });
    }

    pub fn getOrthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4f {
        return Mat4f.init(.{
            .{ 2 / (right - left), 0, 0, 0 },
            .{ 0, 2 / (top - bottom), 0, 0 },
            .{ 0, 0, 2 / (near - far), 0 },
            .{ (left + right) / (left - right), (bottom + top) / (bottom - top), (near + far) / (near - far), 1 },
        });
    }

    pub fn getPerspective(fov: f32, aspect_ratio: f32, near: f32, far: f32) Mat4f {
        const f = math.tan((math.pi * 0.5) - (0.5 * fov));
        const range_inv = 1.0 / (near - far);

        return Mat4f.init(.{
            .{ f / aspect_ratio, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, (near + far) * range_inv, -1 },
            .{ 0, 0, near * far * range_inv * 2, 0 },
        });
    }

    pub fn lookAt(camera_pos: Vec3f, target_pos: Vec3f, up: Vec3f) Mat4f {
        const z_axis = camera_pos.sub(target_pos).normalize();
        const x_axis = up.cross(z_axis).normalize();
        const y_axis = z_axis.cross(x_axis).normalize();

        return Mat4f.init(.{
            .{ x_axis.x(), x_axis.y(), x_axis.z(), 0 },
            .{ y_axis.x(), y_axis.y(), y_axis.z(), 0 },
            .{ z_axis.x(), z_axis.y(), z_axis.z(), 0 },
            .{ camera_pos.x(), camera_pos.y(), camera_pos.z(), 1 },
        });
    }
};

pub fn Vector(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        data: [N]T,

        pub usingnamespace if (N >= 2) struct { 
            pub inline fn x(self: Self) T { return self.data[0]; } 
            pub inline fn y(self: Self) T { return self.data[1]; } 
        } else struct {};

        pub usingnamespace if (N >= 3) struct {
            pub inline fn z(self: Self) T { return self.data[2]; }
        } else struct {};

        pub usingnamespace if (N >= 4) struct {
            pub inline fn w(self: Self) T { return self.data[3]; }
        } else struct {};

        pub fn init(data: [N]T) Self {
            return Self{ .data = data };
        }

        pub fn initValue(value: T) Self {
            var data: [N]T = undefined;
            for (data) |*v| v.* = value;
            return Self{ .data = data };
        }

        pub fn mult(self: Self, scalar: T) Self {
            var result: [N]T = undefined;
            comptime var index = 0;
            inline while (index < N) : (index += 1) {
                result[index] = self.data[index] * scalar;
            }
            return Self.init(result);
        }

        pub fn div(self: Self, scalar: T) error{DivByZero}!Self {
            if (scalar == 0) return error.DivByZero;

            var result: [N]T = undefined;
            comptime var index = 0;
            inline while (index < N) : (index += 1) {
                result[index] = self.data[index] / scalar;
            }
            return Self.init(result);
        }

        pub fn add(self: Self, other: Self) Self {
            var result: [N]T = undefined;
            comptime var index = 0;
            inline while (index < N) : (index += 1) {
                result[index] = self.data[index] + other.data[index];
            }
            return Self.init(result);
        }

        pub fn sub(self: Self, other: Self) Self {
            var result: [N]T = undefined;
            comptime var index = 0;
            inline while (index < N) : (index += 1) {
                result[index] = self.data[index] - other.data[index];
            }
            return Self.init(result);
        }

        pub fn dot(self: Self, other: Self) T {
            @setFloatMode(.Optimized);
            var result: T = 0;
            comptime var index = 0;
            inline while (index < N) : (index += 1) {
                result += self.data[index] * other.data[index];
            }
            return result;
        }

        pub fn cross(self: Self, other: Self) Self {
            @setFloatMode(.Optimized);
            comptime {
                if (N != 3) {
                    @compileError("Cross product requires a 3-Dimensional Vector");
                }
            }
            return Self.init(.{
                self.y() * other.z() - self.z() * other.y(),
                self.z() * other.x() - self.x() * other.z(),
                self.x() * other.y() - self.y() * other.z()
            });
        }

        pub fn normalize(self: Vector(T, N)) Vector(T, N) {
            const sq_sum = blk: {
                var sum: T = 0;
                for (self.data) |v| sum += v * v;
                break :blk sum;
            };
            const length = math.sqrt(sq_sum);
            if (floatEq(length, 0, 0.00001)) {
                return Self.initValue(0);
            } else {
                var result_data: [N]T = undefined;
                for (result_data) |*v, i| v.* = self.data[i] / length;
                return Self.init(result_data);
            }
        }

        pub fn toRowMatrix(self: Vector(T, N)) Matrix(T, 1, N) {
            return Matrix(T, 1, N) {
                .data = [1][N]T{
                    self.data
                }
            };
        }

        pub fn toColumnMatrix(self: Vector(T, N)) Matrix(T, N, 1) {
            var matrix_data: [N][1]T = undefined;
            for (self.data) |d, i| {
                matrix_data[i] = [1]T{ d };
            }

            return .{ .data = matrix_data };
        }
    };
}

pub fn Matrix(comptime T: type, comptime M: usize, comptime N: usize) type {
    return struct {
        const Self = @This();

        data: [N][M]T,

        pub fn init(data: [N][M]T) Self {
            return Self{
                .data = data
            };
        }

        pub fn identity() Self {
            var data: [N][M]T = undefined;
            comptime var row = 0;
            inline while (row < N) : (row += 1) {
                comptime var column = 0;
                inline while (column < M) : (column += 1) {
                    data[row][column] = if (column == row) 1 else 0;
                }
            }

            return Self.init(data);
        }

        pub fn augmentRight(self: Self, other: Self) Matrix(T, M * 2, N) {
            var data: [N][M * 2]T = undefined;
            comptime var row = 0;
            inline while (row < N) : (row += 1) {
                comptime var column = 0;
                inline while (column < M * 2) : (column += 1) {
                    data[row][column] = if (column < M) self.data[row][column] else other.data[row][column - M];
                }
            }
            return Matrix(T, M * 2, N).init(data);
        }

        pub fn flatten(self: Self) [N * M]T {
            var result: [N * M]T = undefined;
            comptime var row = 0;
            inline while (row < N) : (row += 1) {
                comptime var column = 0;
                inline while (column < M) : (column += 1) {
                    result[column + (row * M)] = self.data[row][column];
                }
            }
            return result;
        }

        pub fn getSubmatrix(self: Self, comptime num_rows: usize, comptime num_columns: usize, row_index: usize, column_index: usize) !Matrix(T, num_columns, num_rows) {
            if (row_index + num_rows > N or column_index + num_columns > M) return error.InvalidSize;

            var result: [num_rows][num_columns]T = undefined;
            comptime var row = 0;
            inline while (row < num_rows) : (row += 1) {
                comptime var column = 0;
                inline while (column < num_columns) : (column += 1) {
                    result[row][column] = self.data[row_index + row][column_index + column];
                }
            }

            return Matrix(T, num_columns, num_rows).init(result);
        }

        pub fn getRow(self: Self, row_index: usize) Vector(T, M) {
            return Vector(T, M).init(self.data[row_index]);   
        }

        pub fn getColumn(self: Self, column_index: usize) Vector(T, N) {
            var vec_data: [N]T = undefined;
            comptime var row_index = 0;
            inline while (row_index < N) : (row_index += 1) {
                vec_data[row_index] = self.data[row_index][column_index];
            }
            return Vector(T, N).init(vec_data);
        }

        pub fn add(self: Self, other: Self) Self {
            @setRuntimeSafety(false);
            var result: Self = undefined;
            comptime var i = 0;
            inline while (i < N) : (i += 1) {
                comptime var j = 0;
                inline while (j < M) : (j += 1) {
                    result.data[i][j] = self.data[i][j] + other.data[i][j];
                }
            }
            return result;
        }

        pub fn scalarMult(self: Self, scalar: T) Self {
            @setRuntimeSafety(false);
            var result: Self = undefined;
            comptime var i = 0;
            inline while (i < N) : (i += 1) {
                comptime var j = 0;
                inline while (j < M) : (j += 1) {
                    result.data[i][j] = self.data[i][j] * scalar;
                }
            }
            return result;
        }

        pub fn transpose(self: Self) Matrix(T, N, M) {
            @setRuntimeSafety(false);
            var result: Matrix(T, N, M) = undefined;
            comptime var i = 0;
            inline while (i < M) : (i += 1) {
                comptime var j = 0; 
                inline while (j < N) : (j += 1) {
                    result.data[i][j] = self.data[j][i];
                }
            }
            return result;
        }

        pub fn determinant(self: Self) !T {
            @setFloatMode(.Optimized);
            if (N != M) return error.NotSquare;
            if (N == 1) {
                return self.data[0][0];
            } 
            if (N == 2) {
                return (self.data[0][0] * self.data[1][1]) - (self.data[0][1] * self.data[1][0]);
            }
            
            var result_det: T = 0;
            var current_modifier: T = 1;
            var column_index: usize = 0;
            while (column_index < M) : (column_index += 1) {
                var submatrix: [N - 1][M - 1]T = undefined;
                comptime var sub_row_index = 1;
                inline while (sub_row_index < N) : (sub_row_index += 1) {
                    var sub_column_index: usize = 0;
                    while (sub_column_index < M) : (sub_column_index += 1) {
                        if (sub_column_index != column_index) {
                            const value = self.data[sub_row_index][sub_column_index];
                            const value_dest_column = if (sub_column_index < column_index) sub_column_index else sub_column_index - 1;
                            submatrix[sub_row_index - 1][value_dest_column] = value;
                        }
                    }
                }
                // Recursively determine the determinant of the submatrix
                const submatrix_det = try Matrix(T, M - 1, N - 1).init(submatrix).determinant();
                // Add the partial determinate to the acc. result, alternating + and - 
                result_det += current_modifier * self.data[0][column_index] * submatrix_det;
                current_modifier *= -1;
            }

            return result_det;
        }

        pub fn inverse(self: Self) !Self {
            @setFloatMode(.Optimized);
            const det = try self.determinant();
            if (det == 0) return error.NoInverse;

            var result: Matrix(T, M * 2, N) = self.augmentRight(Self.identity());

            comptime var row_index = 0;
            inline while (row_index < N) : (row_index += 1) {
                // For readability. We always operate on the same column index as the current row index.
                const column_index = row_index;
                const pivot = result.data[row_index][column_index];
                // Divide row by value in pivot index
                if (pivot != 1 and pivot != 0) {
                    const div_result: Vector(T, M * 2) = result.getRow(row_index).div(pivot) catch unreachable;
                    result.data[row_index] = div_result.data;
                }

                // Zero out all other values in column
                comptime var other_row_index = 0;
                inline while (other_row_index < M) : (other_row_index += 1) {
                    if (other_row_index != row_index) {
                        // Multiply the current row by the value at [other_row_index, column_index].
                        const mult_result = result.getRow(row_index).mult(result.data[other_row_index][column_index]);
                        // Subtract the other row by the result of the previous multiplication
                        const sub_result = result.getRow(other_row_index).sub(mult_result);
                        result.data[other_row_index] = sub_result.data;
                    }
                }
            }

            return result.getSubmatrix(N, M, 0, M);
        }

        pub fn eq(self: Self, other: Self) bool {
            @setRuntimeSafety(false);
            comptime var i = 0;
            inline while (i < N) : (i += 1) {
                comptime var j = 0;
                inline while (j < M) : (j += 1) {
                    if (!floatEq(self.data[i][j], other.data[i][j], 0.0001)) {
                        return false;
                    }
                }
            }
            return true;
        }

        pub fn mult(self: Matrix(T, M, N), other: Matrix(T, N, M)) Matrix(T, N, N) {
            var result: Matrix(T, N, N) = undefined;
            comptime var self_row_index = 0;
            inline while (self_row_index < N) : (self_row_index += 1) {
                comptime var other_column_index = 0;
                inline while (other_column_index < N) : (other_column_index += 1) {
                    result.data[self_row_index][other_column_index] = self.getRow(self_row_index).dot(other.getColumn(other_column_index));
                }
            }
            return result;
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            out_stream: anytype,
        ) !void {
            comptime var row_index = 0;
            inline while (row_index < N) : (row_index += 1) {
                try std.fmt.format(out_stream, "\n|", .{});
                comptime var column_index = 0;
                inline while (column_index < M) : (column_index += 1) {
                    try std.fmt.format(out_stream, " {d:.5}", .{self.data[row_index][column_index]});
                    if (column_index < M - 1) {
                        try std.fmt.format(out_stream, ",", .{});
                    }
                }
                try std.fmt.format(out_stream, " |", .{});
            }
        }

    };
}

test "transpose" {
    const m = Matrix(f32, 2, 3).init(.{
        .{ 1, 2 },
        .{ 3, 4 },
        .{ 5, 6 }
    });
    const m_t = m.transpose();

    const expected_transpose = Matrix(f32, 3, 2).init(.{
        .{ 1, 3, 5 },
        .{ 2, 4, 6 }
    });

    std.testing.expect(expected_transpose.eq(m_t));
}

test "add" {
    const M = Matrix(f32, 3, 3);
    const a = M.init(.{
        .{ 1, 2, 3 },
        .{ 4, 5, 6 },
        .{ 7, 8, 9 },
    });
    const b = M.init(.{
        .{ 10, 11, 12 },
        .{ 13, 14, 15 },
        .{ 16, 17, 18 },
    });
    const expected = M.init(.{
        .{ 11, 13, 15 },
        .{ 17, 19, 21 },
        .{ 23, 25, 27 },
    });

    std.testing.expect(expected.eq(a.add(b)));

}

test "scalar multiply" {
    const M = Matrix(f32, 3, 3);
    const a = M.init(.{
        .{ 1, 2, 3 },
        .{ 4, 5, 6 },
        .{ 7, 8, 9 },
    });
    const expected = M.init(.{
        .{ 2, 4, 6 },
        .{ 8, 10, 12 },
        .{ 14, 16, 18 },
    });

    std.testing.expect(expected.eq(a.scalarMult(2)));

}

test "matrix multiply" {
    const m_a = Matrix(f32, 3, 2).init(.{
        .{ 1, 2, 3 },
        .{ 4, 5, 6 }
    });
    const m_b = Matrix(f32, 2, 3).init(.{
        .{ 7, 8 },
        .{ 9, 10 },
        .{ 11, 12 },
    });

    const expected = Matrix(f32, 2, 2).init(.{
        .{ 58, 64 },
        .{ 139, 154 },
    });

    std.testing.expect(expected.eq(m_a.mult(m_b)));
}

test "sample projection times translation" {
    const projection = Mat3f.init(.{
        .{ 0.002857, 0, 0 },
        .{ 0, -0.002857, 0 },
        .{ -1, 1, 1 },
    });

    const translation = Mat3f.init(.{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 100, 300, 1 },
    });

    const expected = Mat3f.init(.{
        .{ 0.002857, 0, 0 },
        .{ 0, -0.002857, 0 },
        .{ 99, 301, 1 },
    });

    std.testing.expect(expected.eq(projection.mult(translation)));
}

test "flatten matrix" {
    const m = Matrix(f32, 3, 2).init(.{
        [_]f32{ 1, 2, 3 },
        [_]f32{ 4, 5, 6 }
    });

    const expected = [6]f32{ 1, 2, 3, 4, 5, 6 };

    const res = m.flatten();

    std.testing.expectEqualSlices(f32, expected[0..], res[0..]);
}

test "identity matrix" {
    const id = Matrix(f32, 3, 3).identity();
    const expected = Matrix(f32, 3, 3).init(.{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    });

    std.testing.expect(id.eq(expected));
}

test "inverse matrix 2x2" {
    const m = Matrix(f32, 2, 2).init(.{
        .{ 5, 3 },
        .{ 10, 8 }
    });

    const expected_inverse = Matrix(f32, 2, 2).init(.{
        .{ (4.0 / 5.0), (-3.0 / 10.0) },
        .{ -1, 0.5 }
    });

    const actual_inverse = try m.inverse();

    std.testing.expect(actual_inverse.eq(expected_inverse));
}

test "inverse matrix 4x4" {
    const m = Mat4f.init(.{
        .{ -18, 22, 3, 55 },
        .{ 1, 1, 29, -11 },
        .{ 0, 2, 44, 0 },
        .{ 37, 37, 0, 1 },
    });

    const expected_inverse = Mat4f.init(.{
        .{ -8947.0 / 298279.0, -44289/298279.0, 59601/596558.0, 4906/298279.0 },
        .{ 8976/298279.0, 45166/298279.0, -60761/596558.0, 3146/298279.0},
        .{ -408/298279.0, -2053/298279.0, 8160/298279.0, -143/298279.0},
        .{ -1073/298279.0, -32449/298279.0, 21460/298279.0, 355/298279.0},
    });

    const actual_inverse = try m.inverse();

    std.testing.expect(expected_inverse.eq(actual_inverse));
}

test "determinant" {
    const m = Mat3f.init(.{
        .{ 6, 1, 1 },
        .{ 4, -2, 5 },
        .{ 2, 8, 7 },
    });

    const expected_det: f32 = -306;
    const actual_det = try m.determinant();

    std.testing.expectEqual(expected_det, actual_det);
}

