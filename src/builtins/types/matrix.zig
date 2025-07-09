const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const matrix_helpers = @import("../helpers/matrix.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

const StdMethod = builtins.StdMethod;
const StdCtor = builtins.StdCtor;

const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectNumberArrays = builtins.expectNumberArrays;

fn expectMatrix(val: *Value, module_name: []const u8, func_name: []const u8) !*MatrixInstance {
    const writer_err = driver.getWriterErr();
    const name = try builtins.getStdStructName(val);
    if (std.mem.eql(u8, name, "matrix")) {
        return try getMatrixInstance(val);
    } else {
        try writer_err.print("{s} module: {s} expected a matrix argument but got a(n) {s}\n", .{ module_name, func_name, name });
        return error.ExpectedMatrixArg;
    }
}

pub const MatrixInstance = struct {
    matrix: []const std.ArrayList(f64),
    rows: usize,
    cols: usize,
    size: usize,
};

fn getMatrixInstance(this: *Value) !*MatrixInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var MATRIX_METHODS: std.StringHashMap(StdMethod) = undefined;
var MATRIX_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    MATRIX_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try MATRIX_METHODS.put("get", matrixGet);
    try MATRIX_METHODS.put("set", matrixSet);
    try MATRIX_METHODS.put("transpose", matrixTranspose);
    try MATRIX_METHODS.put("equals", matrixEquals);
    try MATRIX_METHODS.put("add", matrixAdd);
    try MATRIX_METHODS.put("sub", matrixSub);
    try MATRIX_METHODS.put("scale", matrixScale);
    try MATRIX_METHODS.put("mul", matrixMul);
    try MATRIX_METHODS.put("inverse", matrixInverse);
    try MATRIX_METHODS.put("dim", matrixItems);
    try MATRIX_METHODS.put("items", matrixItems);
    try MATRIX_METHODS.put("size", matrixSize);
    try MATRIX_METHODS.put("rows", matrixRows);
    try MATRIX_METHODS.put("cols", matrixCols);
    try MATRIX_METHODS.put("str", matrixStr);

    MATRIX_TYPE = .{
        .std_struct = .{
            .name = "matrix",
            .constructor = matrixConstructor,
            .methods = MATRIX_METHODS,
        },
    };

    return MATRIX_TYPE;
}

fn matrixConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len == 0) {
        try writer_err.print("matrix(args..) expects at least 1 argument but got 0\n", .{});
        return error.ArgumentCountMismatch;
    }

    const nested: []const []const f64 = blk: {
        // Case 1: matrix(dim) → square identity matrix
        if (args.len == 1) {
            const val = try eval.evalExpr(args[0], env);
            if (val == .number) {
                const dim: usize = @intFromFloat(val.number);
                if (dim < 1) {
                    try writer_err.print("matrix(dim): dimension must be at least 1, got {d}\n", .{dim});
                    return error.ArraySizeMismatch;
                }

                var result = std.ArrayList([]const f64).init(env.allocator);
                defer result.deinit();

                for (0..dim) |i| {
                    var row = try std.ArrayList(f64).initCapacity(env.allocator, dim);
                    for (0..dim) |j| {
                        try row.append(if (i == j) 1.0 else 0.0);
                    }
                    try result.append(try row.toOwnedSlice());
                }

                break :blk try result.toOwnedSlice();
            }

            // Case 2: matrix([ [..], [..] ]) — nested rows
            const outer_array = try expectArrayArgs(args, env, 1, "matrix", "ctor");
            break :blk try expectNumberArrays(env.allocator, outer_array, "matrix", "ctor");
        }

        // Case 3: matrix([..], [..], ...) — multiple row arrays
        if (args.len >= 2) {
            const rows = try expectArrayArgs(args, env, args.len, "matrix", "ctor");
            break :blk try expectNumberArrays(env.allocator, rows, "matrix", "ctor");
        }

        try writer_err.print("matrix(args..) expects either 1 nested array or at least 2 row arrays, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    };

    const row_count = nested.len;
    if (row_count < 1) {
        try writer_err.print("matrix(args..): matrix must have at least 1 rows, got {d}\n", .{row_count});
        return error.ArraySizeMismatch;
    }

    const col_count = nested[0].len;
    if (col_count < 1) {
        try writer_err.print("matrix(args..): matrix rows must have at least 1 columns, got {d} in first row\n", .{col_count});
        return error.ArraySizeMismatch;
    }

    for (nested, 0..) |row, i| {
        if (row.len != col_count) {
            try writer_err.print("matrix(args..): matrix row {d} has {d} columns, expected {d}\n", .{ i, row.len, col_count });
            return error.ArraySizeMismatch;
        }
    }

    var rows = try env.allocator.alloc(std.ArrayList(f64), row_count);
    for (nested, 0..) |row_data, i| {
        var row = try std.ArrayList(f64).initCapacity(env.allocator, col_count);
        try row.appendSlice(row_data);
        rows[i] = row;
    }

    const wrapped = try env.allocator.create(MatrixInstance);
    wrapped.* = .{
        .matrix = rows,
        .rows = row_count,
        .cols = col_count,
        .size = row_count * col_count,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "matrix",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = MATRIX_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

pub fn matrixGet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const parts= try builtins.expectNumberArgs(args, env, 2, "matrix", "get");

    const row: i64 = @intFromFloat(parts[0]);
    const col: i64 = @intFromFloat(parts[1]);

    const inst = try getMatrixInstance(this);
    if (row >= inst.matrix.len or col >= inst.matrix[0].items.len) {
        try writer_err.print("matrix.get({d}, {d}) out of bounds\n", .{ row, col });
        return error.IndexOutOfBounds;
    }

    return .{
        .number = inst.matrix[@intCast(row)].items[@intCast(col)],
    };
}

pub fn matrixSet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("matrix.set(row, col, value) expects 3 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const row_val = try eval.evalExpr(args[0], env);
    const col_val = try eval.evalExpr(args[1], env);
    const value_val = try eval.evalExpr(args[2], env);

    if (row_val != .number or col_val != .number or value_val != .number) {
        try writer_err.print("matrix.set(row, col, value) expects all numeric arguments\n", .{});
        return error.TypeMismatch;
    }

    const row: i64 = @intFromFloat(row_val.number);
    const col: i64 = @intFromFloat(col_val.number);

    const inst = try getMatrixInstance(this);
    if (row >= inst.matrix.len or col >= inst.matrix[0].items.len) {
        try writer_err.print("matrix.set({d}, {d}) out of bounds\n", .{ row, col });
        return error.IndexOutOfBounds;
    }

    inst.matrix[@intCast(row)].items[@intCast(col)] = value_val.number;
    return this.*;
}

pub fn matrixTranspose(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.transpose() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    const rows = inst.rows;
    const cols = inst.cols;

    var transposed = try env.allocator.alloc(std.ArrayList(f64), cols);
    for (0..cols) |i| {
        transposed[i] = try std.ArrayList(f64).initCapacity(env.allocator, rows);
    }

    for (inst.matrix, 0..inst.matrix.len) |row, _| {
        for (row.items, 0..) |val, c| {
            try transposed[c].append(val);
        }
    }

    const wrapped = try env.allocator.create(MatrixInstance);
    wrapped.* = .{
        .matrix = transposed,
        .rows = inst.rows,
        .cols = inst.cols,
        .size = inst.size,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "matrix",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = MATRIX_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

pub fn matrixEquals(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("matrix.equals(other_matrix) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    var other_val = try eval.evalExpr(args[0], env);
    const a = try getMatrixInstance(this);
    const b = try expectMatrix(&other_val, "matrix", "equals");

    if (a.matrix.len != b.matrix.len or a.matrix[0].items.len != b.matrix[0].items.len)
        return .{
            .boolean = false,
        };

    for (a.matrix, 0..) |row_a, i| {
        for (row_a.items, 0..) |val, j| {
            if (val != b.matrix[i].items[j]) {
                return .{
                    .boolean = false,
                };
            }
        }
    }

    return .{
        .boolean = true,
    };
}

pub fn matrixAdd(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("matrix.add(other_matrix) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    var other_val = try eval.evalExpr(args[0], env);
    const a = try getMatrixInstance(this);
    const b = try expectMatrix(&other_val, "matrix", "add");

    if (a.matrix.len != b.matrix.len or a.matrix[0].items.len != b.matrix[0].items.len) {
        try writer_err.print("matrix.add(): size mismatch\n", .{});
        return error.VectorSizeMismatch;
    }

    for (a.matrix, 0..) |row_a, i| {
        for (row_a.items, 0..) |*val_a, j| {
            val_a.* += b.matrix[i].items[j];
        }
    }

    return this.*;
}

pub fn matrixSub(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("matrix.sub(other_matrix) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    var other_val = try eval.evalExpr(args[0], env);
    const a = try getMatrixInstance(this);
    const b = try expectMatrix(&other_val, "matrix", "sub");

    if (a.matrix.len != b.matrix.len or a.matrix[0].items.len != b.matrix[0].items.len) {
        try writer_err.print("matrix.sub(): size mismatch\n", .{});
        return error.VectorSizeMismatch;
    }

    for (a.matrix, 0..) |row_a, i| {
        for (row_a.items, 0..) |*val_a, j| {
            val_a.* -= b.matrix[i].items[j];
        }
    }

    return this.*;
}

pub fn matrixScale(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const scalar = (try expectNumberArgs(args, env, 1, "matrix", "scale"))[0];
    const inst = try getMatrixInstance(this);

    for (inst.matrix) |row| {
        for (row.items) |*val| {
            val.* *= scalar;
        }
    }

    return this.*;
}

pub fn matrixMul(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("matrix.mul(other_matrix|vector) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    const lhs_rows = inst.rows;
    const lhs_cols = inst.cols;

    var rhs_val = try eval.evalExpr(args[0], env);

    // === Matrix * Matrix ===
    if (rhs_val == .std_instance and std.mem.eql(u8, try builtins.getStdStructName(&rhs_val), "matrix")) {
        const rhs = try getMatrixInstance(&rhs_val);
        const rhs_rows = rhs.rows;
        const rhs_cols = rhs.cols;

        if (lhs_cols != rhs_rows) {
            try writer_err.print("matrix.mul(matrix): incompatible dimensions {d}x{d} * {d}x{d}\n", .{ lhs_rows, lhs_cols, rhs_rows, rhs_cols });
            return error.InvalidShape;
        }

        var result = try env.allocator.alloc(std.ArrayList(f64), lhs_rows);
        for (0..lhs_rows) |i| {
            result[i] = try std.ArrayList(f64).initCapacity(env.allocator, rhs_cols);
            for (0..rhs_cols) |j| {
                var sum: f64 = 0;
                for (0..lhs_cols) |k| {
                    sum += inst.matrix[i].items[k] * rhs.matrix[k].items[j];
                }
                try result[i].append(sum);
            }
        }

        const wrapped = try env.allocator.create(MatrixInstance);
        wrapped.* = .{
            .matrix = result,
            .rows = lhs_rows,
            .cols = lhs_cols,
            .size = lhs_rows * lhs_cols,
        };

        const internal_ptr = try env.allocator.create(Value);
        internal_ptr.* = .{
            .typed_val = .{
                .value = @ptrCast(@alignCast(wrapped)),
                ._type = "matrix",
            },
        };

        var fields = std.StringHashMap(*Value).init(env.allocator);
        try fields.put("__internal", internal_ptr);

        const type_ptr = try env.allocator.create(Value);
        type_ptr.* = MATRIX_TYPE;

        return .{
            .std_instance = .{
                ._type = type_ptr,
                .fields = fields,
            },
        };
    }

    // === Matrix * Vector ===
    if (rhs_val == .std_instance and std.mem.eql(u8, try builtins.getStdStructName(&rhs_val), "vector")) {
        const vector = @import("vector.zig");
        const rhs = try vector.getVectorInstance(&rhs_val);
        const rhs_len = rhs.vector.items.len;

        if (lhs_cols != rhs_len) {
            try writer_err.print("matrix.mul(vector): matrix has {d} cols but vector has {d} elements\n", .{ lhs_cols, rhs_len });
            return error.InvalidShape;
        }

        var result = try std.ArrayList(f64).initCapacity(env.allocator, lhs_rows);
        for (inst.matrix) |row| {
            var sum: f64 = 0;
            for (row.items, 0..) |val, j| {
                sum += val * rhs.vector.items[j];
            }
            try result.append(sum);
        }

        const wrapped = try env.allocator.create(vector.VectorInstance);
        wrapped.* = .{ .vector = result };

        const internal_ptr = try env.allocator.create(Value);
        internal_ptr.* = .{
            .typed_val = .{
                .value = @ptrCast(@alignCast(wrapped)),
                ._type = "vector",
            },
        };

        var fields = std.StringHashMap(*Value).init(env.allocator);
        try fields.put("__internal", internal_ptr);

        const type_ptr = try env.allocator.create(Value);
        type_ptr.* = vector.VECTOR_TYPE;

        return .{
            .std_instance = .{
                ._type = type_ptr,
                .fields = fields,
            },
        };
    }

    try writer_err.print("matrix.mul(other): expected matrix or vector, got {s}\n", .{@tagName(rhs_val)});
    return error.TypeMismatch;
}

pub fn matrixInverse(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.inverse() takes no arguments\n", .{});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    const n = inst.rows;
    const m = inst.cols;

    if (n != m) {
        try writer_err.print("matrix.inverse(): only square matrices are invertible, got {d}x{d}\n", .{ n, m });
        return error.InvalidShape;
    }

    const inv_matrix = switch (n) {
        2 => try matrix_helpers.inverse2x2(inst.matrix, env.allocator),
        3 => try matrix_helpers.inverse3x3(inst.matrix, env.allocator),
        4 => try matrix_helpers.inverse4x4(inst.matrix, env.allocator),
        else => {
            try writer_err.print("matrix.inverse(): only 2x2-4x4 supported, got {d}x{d}\n", .{ n, m });
            return error.UnsupportedSize;
        },
    };

    const wrapped = try env.allocator.create(MatrixInstance);
    wrapped.* = .{
        .matrix = inv_matrix,
        .rows = n,
        .cols = m,
        .size = n * m,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "matrix",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = MATRIX_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn matrixItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.items() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    var result = try std.ArrayList(Value).initCapacity(env.allocator, inst.size);
    for (inst.matrix) |row| {
        var row_arr = try std.ArrayList(Value).initCapacity(env.allocator, inst.size);
        for (row.items) |row_val| {
            try row_arr.append(.{
                .number = row_val,
            });
        }

        try result.append(.{
            .array = row_arr,
        });
    }

    return .{
        .array = result,
    };
}

fn matrixSize(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.size() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.size),
    };
}

pub fn matrixRows(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.rows() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.rows),
    };
}

pub fn matrixCols(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.cols() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.cols),
    };
}

fn matrixStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("matrix.str() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .string = try toString(env.allocator, inst),
    };
}

pub fn toString(allocator: std.mem.Allocator, matrix: *MatrixInstance) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    for (0..matrix.rows) |i| {
        const row = matrix.matrix[i];
        for (0..row.items.len) |j| {
            try writer.print("{d} ", .{row.items[j]});
        }
        if (i != matrix.rows - 1) {
            try writer.print("\n", .{});
        }
    }

    return try buffer.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "matrix_builtin_2d" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import matrix;
        \\let m = new matrix([1.0, 2.0], [3.0, 4.0]);
        \\let orig = m.str();
        \\let get00 = m.get(0, 0);
        \\let get01 = m.get(0, 1);
        \\m.set(1, 1, 9.0);
        \\let get11 = m.get(1, 1);
        \\m.scale(0.5);
        \\let scaled = m.str();
        \\let rows = m.rows();
        \\let cols = m.cols();
        \\let size = m.size();
        \\let items = m.items();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    try testing.expectEqualStrings("1 2 \n3 4 ", (try env.get("orig")).string);
    try testing.expectEqual(@as(f64, 1.0), (try env.get("get00")).number);
    try testing.expectEqual(@as(f64, 2.0), (try env.get("get01")).number);
    try testing.expectEqual(@as(f64, 9.0), (try env.get("get11")).number);
    try testing.expectEqualStrings("0.5 1 \n1.5 4.5 ", (try env.get("scaled")).string);
    try testing.expectEqual(@as(f64, 2), (try env.get("rows")).number);
    try testing.expectEqual(@as(f64, 2), (try env.get("cols")).number);
    try testing.expectEqual(@as(f64, 4), (try env.get("size")).number);
    try testing.expect((try env.get("items")).array.items.len == 2);
}

test "matrix_builtin_3d" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import matrix;
        \\let m = new matrix([1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]);
        \\let inverse = m.inverse();
        \\let same = inverse.equals(m);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    try testing.expectEqual(@as(bool, true), (try env.get("same")).boolean);
}

test "matrix_builtin_4d" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import matrix;
        \\let m = new matrix(4);
        \\let orig = m.str();
        \\let inv = m.inverse();
        \\let reinv = inv.inverse();
        \\let roundtrip = reinv.equals(m);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    try testing.expectEqual(@as(bool, true), (try env.get("roundtrip")).boolean);
}

test "matrix_builtin_rectangular" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import matrix;
        \\let m = new matrix([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]);
        \\let str = m.str();
        \\let rows = m.rows();
        \\let cols = m.cols();
        \\let mul = m.mul(new matrix([1.0], [0.0], [1.0]));
        \\let result = mul.str();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    try testing.expectEqualStrings("1 2 3 \n4 5 6 ", (try env.get("str")).string);
    try testing.expectEqual(@as(f64, 2), (try env.get("rows")).number);
    try testing.expectEqual(@as(f64, 3), (try env.get("cols")).number);
    try testing.expectEqualStrings("4 \n10 ", (try env.get("result")).string);
}
