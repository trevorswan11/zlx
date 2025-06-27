const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
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
    try MATRIX_METHODS.put("dim", matrixItems);
    try MATRIX_METHODS.put("items", matrixItems);
    try MATRIX_METHODS.put("size", matrixSize);
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
        // Case 1: matrix([ [1,2], [3,4] ]) or identity matrix
        if (args.len == 1) {
            const val = try eval.evalExpr(args[0], env);
            if (val == .number) {
                const dim: usize = @intFromFloat(val.number);
                if (dim < 2 or dim > 4) {
                    try writer_err.print("matrix(dim): identity matrix only supported for dim in [2,4], got {d}\n", .{dim});
                    return error.ArraySizeMismatch;
                }

                // Construct the identity matrix with the given dimension
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

            // Case 2: matrix([ [..], [..] ]) — nested array
            const outer_array = try expectArrayArgs(args, env, 1, "matrix", "ctor");
            break :blk try expectNumberArrays(env.allocator, outer_array, "matrix", "ctor");
        }

        // Case 2: matrix([1,2], [3,4]), matrix([1,2,3], [4,5,6], ...), etc...
        if (args.len >= 2 and args.len <= 4) {
            const rows = try expectArrayArgs(args, env, args.len, "matrix", "ctor");
            break :blk try expectNumberArrays(env.allocator, rows, "matrix", "ctor");
        }

        try writer_err.print(
            "matrix(args..) expects either 1 argument (nested array) or 2-4 row arrays, got {d}\n",
            .{args.len},
        );
        return error.ArgumentCountMismatch;
    };

    const row_count = nested.len;
    if (row_count < 2 or row_count > 4) {
        try writer_err.print("matrix(args...): matrix must have 2-4 rows, got {d}\n", .{row_count});
        return error.ArraySizeMismatch;
    }

    const col_count = nested[0].len;
    if (col_count < 2 or col_count > 4) {
        try writer_err.print("matrix(args...): rows must each have 2-4 columns, got {d} in first row\n", .{col_count});
        return error.ArraySizeMismatch;
    }

    for (nested, 0..) |row, i| {
        if (row.len != col_count) {
            try writer_err.print("matrix(args...): row {d} has {d} columns, expected {d}\n", .{ i, row.len, col_count });
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
        .size = row_count,
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

    for (0..matrix.size) |i| {
        for (0..matrix.size) |j| {
            const node = matrix.matrix[i].items[j];
            try writer.print("{d} ", .{node});
        }
        try writer.print("\n", .{});
    }
    _ = buffer.pop();

    return try buffer.toOwnedSlice();
}