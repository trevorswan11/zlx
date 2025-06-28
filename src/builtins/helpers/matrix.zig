const std = @import("std");

pub fn inverse2x2(matrix: []const std.ArrayList(f64), allocator: std.mem.Allocator) ![]std.ArrayList(f64) {
    const a = matrix[0].items[0];
    const b = matrix[0].items[1];
    const c = matrix[1].items[0];
    const d = matrix[1].items[1];

    const det = a * d - b * c;
    if (det == 0) {
        return error.DivisionByZero;
    }

    var result = try allocator.alloc(std.ArrayList(f64), 2);
    for (0..2) |i| result[i] = try std.ArrayList(f64).initCapacity(allocator, 2);

    try result[0].append(d / det);
    try result[0].append(-b / det);
    try result[1].append(-c / det);
    try result[1].append(a / det);

    return result;
}

pub fn inverse3x3(matrix: []const std.ArrayList(f64), allocator: std.mem.Allocator) ![]std.ArrayList(f64) {
    const Helper = struct {
        fn det2(a: f64, b: f64, c: f64, d: f64) f64 {
            return a * d - b * c;
        }

        pub fn minor(mat: []const std.ArrayList(f64), row: usize, col: usize) f64 {
            var m = [4]f64{ 0, 0, 0, 0 };
            var idx: usize = 0;
            for (0..3) |i| {
                if (i == row) continue;
                for (0..3) |j| {
                    if (j == col) continue;
                    m[idx] = mat[i].items[j];
                    idx += 1;
                }
            }
            return det2(m[0], m[1], m[2], m[3]);
        }
    };

    const minor = Helper.minor;

    const det =
        matrix[0].items[0] * minor(matrix, 0, 0) -
        matrix[0].items[1] * minor(matrix, 0, 1) +
        matrix[0].items[2] * minor(matrix, 0, 2);

    if (det == 0) {
        return error.DivisionByZero;
    }

    var cof = try allocator.alloc(std.ArrayList(f64), 3);
    for (0..3) |i| cof[i] = try std.ArrayList(f64).initCapacity(allocator, 3);

    for (0..3) |i| {
        for (0..3) |j| {
            const sign: f64 = if ((i + j) % 2 == 0) 1 else -1;
            const c = sign * minor(matrix, i, j);
            try cof[i].append(c);
        }
    }

    var transposed = try allocator.alloc(std.ArrayList(f64), 3);
    for (0..3) |i| transposed[i] = try std.ArrayList(f64).initCapacity(allocator, 3);

    for (0..3) |i| {
        for (0..3) |j| {
            try transposed[i].append(cof[j].items[i] / det);
        }
    }

    return transposed;
}

pub fn inverse4x4(matrix: []const std.ArrayList(f64), allocator: std.mem.Allocator) ![]std.ArrayList(f64) {
    const size = 4;
    var a = try allocator.alloc([8]f64, 4);
    for (0..size) |i| {
        for (0..size) |j| {
            a[i][j] = matrix[i].items[j];
            a[i][j + size] = if (i == j) 1.0 else 0.0;
        }
    }

    // Forward elimination
    for (0..size) |i| {
        const pivot = a[i][i];
        if (pivot == 0) {
            return error.DivisionByZero;
        }

        for (0..2 * size) |j| {
            a[i][j] /= pivot;
        }

        for (0..size) |k| {
            if (k == i) continue;
            const factor = a[k][i];
            for (0..2 * size) |j| {
                a[k][j] -= factor * a[i][j];
            }
        }
    }

    var result = try allocator.alloc(std.ArrayList(f64), size);
    for (0..size) |i| {
        result[i] = try std.ArrayList(f64).initCapacity(allocator, size);
        for (0..size) |j| {
            try result[i].append(a[i][j + size]);
        }
    }

    return result;
}
