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
    if (true) {
        return error.TODO;
    }
    const writer_err = driver.getWriterErr();
    if (args.len == 0) {
        try writer_err.print("vector(args..) expects at least 1 arguments but got 0\n", .{});
        return error.ArgumentCountMismatch;
    }

    const mat: []const std.ArrayList(f64) = blk: switch (args.len) {
        // Vector can be created out of an array
        1 => {
            const arg_arrays = try expectArrayArgs(args, env, 1, "vector", "ctor");
            const vals = (try expectNumberArrays(env.allocator, arg_arrays, "vector", "ctor"))[0];
            if (vals.len == 0 or vals.len > 4) {
                try writer_err.print("vector(array) expects an array of size 4 or less, found an array length {d}\n", .{vals.len});
                return error.ArraySizeMismatch;
            }
            break :blk vals;
        },

        2 => break :blk try expectNumberArgs(args, env, 2, "vector", "ctor"),
        3 => break :blk try expectNumberArgs(args, env, 3, "vector", "ctor"),
        4 => break :blk try expectNumberArgs(args, env, 4, "vector", "ctor"),
        else => {
            try writer_err.print("vector(args..) expects a maximum of 4 arguments but got {d}\n", .{args.len});
            return error.ArgumentCountMismatch;
        },
    };

    var arr = try std.ArrayList(f64).initCapacity(env.allocator, mat.len);
    try arr.appendSlice(mat);
    const wrapped = try env.allocator.create(MatrixInstance);
    wrapped.* = .{
        .vector = arr,
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
