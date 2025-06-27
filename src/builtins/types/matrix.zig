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
