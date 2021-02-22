const std = @import("std");
const math = std.math;

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
        return Mat3f.init([3][3]f32{
            [_]f32{ 1, 0, 0 },
            [_]f32{ 0, 1, 0 },
            [_]f32{ tx, ty, 1 },
        });
    }
    
    pub fn getRotation(radians: f32) Mat3f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat3f.init([3][3]f32{
            [_]f32{ c, -s, 0 },
            [_]f32{ s,  c, 0 },
            [_]f32{ 0,  0, 1 },
        });
    }

    pub fn getScaling(sx: f32, sy: f32) Mat3f {
        return Mat3f.init([3][3]f32{
            [_]f32{ sx, 0, 0 },
            [_]f32{ 0, sy, 0 },
            [_]f32{ 0, 0, 1 },
        });
    }

    pub fn getProjection(width: f32, height: f32) Mat3f {
        return Mat3f.init([3][3]f32{
            [_]f32{ 2 / width, 0, 0 },
            [_]f32{ 0, -2 / height, 0 },
            [_]f32{ -1, 1, 1 }
        });
    }
};

pub const Mat3D = struct {
    pub fn getTranslation(tx: f32, ty: f32, tz: f32) Mat4f {
        return Mat4f.init([4][4]f32{
            [_]f32{ 1, 0, 0, 0 },
            [_]f32{ 0, 1, 0, 0 },
            [_]f32{ 0, 0, 1, 0 },
            [_]f32{ tx, ty, tz, 1 },
        });
    }

    pub fn getXRotation(radians: f32) Mat4f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat4f.init([4][4]f32{
            [_]f32{ 1, 0, 0, 0 },
            [_]f32{ 0, c, s, 0 },
            [_]f32{ 0, -s, c, 0 },
            [_]f32{ 0, 0, 0, 1 },
        });
    }

    pub fn getYRotation(radians: f32) Mat4f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat4f.init([4][4]f32{
            [_]f32{ c, 0, -s, 0 },
            [_]f32{ 0, 1, 0, 0 },
            [_]f32{ s, 0, c, 0 },
            [_]f32{ 0, 0, 0, 1 },
        });
    }

    pub fn getZRotation(radians: f32) Mat4f {
        const c = math.cos(radians);
        const s = math.sin(radians);
        return Mat4f.init([4][4]f32{
            [_]f32{ c, s, 0, 0 },
            [_]f32{ -s, c, 0, 0 },
            [_]f32{ 0, 0, 1, 0 },
            [_]f32{ 0, 0, 0, 1 },
        });
    }

    pub fn getScaling(sx: f32, sy: f32, sz: f32) Mat4f {
        return Mat4f.init([4][4]f32{
            [_]f32{ sx, 0, 0, 0 },
            [_]f32{ 0, sy, 0, 0 },
            [_]f32{ 0, 0, sz, 0 },
            [_]f32{ 0, 0, 0, 1 },
        });
    }

    pub fn getProjection(width: f32, height: f32, depth: f32) Mat4f {
        return Mat4f.init([4][4]f32{
            [_]f32{ 2 / width, 0, 0, 0 },
            [_]f32{ 0, -2 / height, 0, 0 },
            [_]f32{ 0, 0, 2 / depth, 0 },
            [_]f32{ -1, 1, 0, 1 },
        });
    }

    pub fn getOrthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4f {
        return Mat4f.init([4][4]f32{
            [_]f32{ 2 / (right - left), 0, 0, 0 },
            [_]f32{ 0, 2 / (top - bottom), 0, 0 },
            [_]f32{ 0, 0, 2 / (near - far), 0 },
            [_]f32{ (left + right) / (left - right), (bottom + top) / (bottom - top), (near + far) / (near - far), 1 },
        });
    }

    pub fn getPerspective(fov: f32, aspect_ratio: f32, near: f32, far: f32) Mat4f {
        const f = math.tan((math.pi * 0.5) - (0.5 * fov));
        const range_inv = 1.0 / (near - far);

        return Mat4f.init([4][4]f32{
            [_]f32{ f / aspect_ratio, 0, 0, 0 },
            [_]f32{ 0, f, 0, 0 },
            [_]f32{ 0, 0, (near + far) * range_inv, -1 },
            [_]f32{ 0, 0, near * far * range_inv * 2, 0 },
        });
    }
};

pub fn Vector(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        data: [N]T,

        pub fn init(data: [N]T) Self {
            return Self{ .data = data };
        }

        pub fn dot(self: Self, other: Self) T {
            var result: T = 0;
            comptime var index = 0;
            inline while (index < N) : (index += 1) {
                result += self.data[index] * other.data[index];
            }
            return result;
        }

        pub fn cross(self: Self, other: Self) Self {
            comptime {
                if (N != 3) {
                    @compileError("Cross product requires a 3-Dimensional Vector");
                }
            }
            return Self{
                .data = [N]T{ 
                    self.data[1] * other.data[2] - self.data[2] * other.data[1],
                    self.data[2] * other.data[0] - self.data[0] * other.data[2],
                    self.data[0] * other.data[1] - self.data[1] * other.data[0]
                }
            };
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

        pub fn eq(self: Self, other: Self) bool {
            @setRuntimeSafety(false);
            comptime var i = 0;
            inline while (i < N) : (i += 1) {
                comptime var j = 0;
                inline while (j < M) : (j += 1) {
                    if (self.data[i][j] != other.data[i][j]) {
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
    const m = Matrix(f32, 2, 3).init([3][2]f32{
        [_]f32{ 1, 2 },
        [_]f32{ 3, 4 },
        [_]f32{ 5, 6 }
    });
    const m_t = m.transpose();

    const expected_transpose = Matrix(f32, 3, 2).init([2][3]f32{
        [_]f32{ 1, 3, 5 },
        [_]f32{ 2, 4, 6 }
    });

    std.testing.expect(expected_transpose.eq(m_t));
}

test "add" {
    const M = Matrix(f32, 3, 3);
    const a = M.init([3][3]f32{
        [_]f32 { 1, 2, 3 },
        [_]f32 { 4, 5, 6 },
        [_]f32 { 7, 8, 9 },
    });
    const b = M.init([3][3]f32{
        [_]f32 { 10, 11, 12 },
        [_]f32 { 13, 14, 15 },
        [_]f32 { 16, 17, 18 },
    });
    const expected = M.init([3][3]f32{
        [_]f32 { 11, 13, 15 },
        [_]f32 { 17, 19, 21 },
        [_]f32 { 23, 25, 27 },
    });

    std.testing.expect(expected.eq(a.add(b)));

}

test "scalar multiply" {
    const M = Matrix(f32, 3, 3);
    const a = M.init([3][3]f32{
        [_]f32 { 1, 2, 3 },
        [_]f32 { 4, 5, 6 },
        [_]f32 { 7, 8, 9 },
    });
    const expected = M.init([3][3]f32{
        [_]f32 { 2, 4, 6 },
        [_]f32 { 8, 10, 12 },
        [_]f32 { 14, 16, 18 },
    });

    std.testing.expect(expected.eq(a.scalarMult(2)));

}

test "matrix multiply" {
    const m_a = Matrix(f32, 3, 2).init([2][3]f32{
        [_]f32{ 1, 2, 3 },
        [_]f32{ 4, 5, 6 }
    });
    const m_b = Matrix(f32, 2, 3).init([3][2]f32{
        [_]f32{ 7, 8 },
        [_]f32{ 9, 10 },
        [_]f32{ 11, 12 },
    });

    const expected = Matrix(f32, 2, 2).init([2][2]f32{
        [_]f32 { 58, 64 },
        [_]f32 { 139, 154 },
    });

    std.testing.expect(expected.eq(m_a.mult(m_b)));
}

test "sample projection times translation" {
    const projection = Mat3f.init([3][3]f32{
        [_]f32{ 0.002857, 0, 0 },
        [_]f32{ 0, -0.002857, 0 },
        [_]f32{ -1, 1, 1 },
    });

    const translation = Mat3f.init([3][3]f32{
        [_]f32{ 1, 0, 0 },
        [_]f32{ 0, 1, 0 },
        [_]f32{ 100, 300, 1 },
    });

    const expected = Mat3f.init([3][3]f32{
        [_]f32{ 0.002857, 0, 0 },
        [_]f32{ 0, -0.002857, 0 },
        [_]f32{ 99, 301, 1 },
    });

    std.testing.expect(expected.eq(projection.mult(translation)));
}

test "flatten matrix" {
    const m = Matrix(f32, 3, 2).init([2][3]f32{
        [_]f32{ 1, 2, 3 },
        [_]f32{ 4, 5, 6 }
    });

    const expected = [6]f32{ 1, 2, 3, 4, 5, 6 };

    const res = m.flatten();

    std.testing.expectEqualSlices(f32, expected[0..], res[0..]);
}

