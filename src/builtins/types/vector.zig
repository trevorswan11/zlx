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

pub const VectorInstance = struct {
    vector: std.ArrayList(f64),
};

fn getTreapInstance(this: *Value) !*VectorInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var VECTOR_METHODS: std.StringHashMap(StdMethod) = undefined;
var VECTOR_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    VECTOR_METHODS = std.StringHashMap(StdMethod).init(allocator);

    VECTOR_TYPE = .{
        .std_struct = .{
            .name = "vector",
            .constructor = vectorConstructor,
            .methods = VECTOR_METHODS,
        },
    };

    return VECTOR_TYPE;
}

fn vectorConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 0) {
        try writer_err.print("vector(args..) expects at least 1 arguments but got 0\n", .{});
        return error.ArgumentCountMismatch;
    }

    const vec: []f64 = blk: switch (args.len) {
        // Vector can be created out of an array
        1 => {
            const arg = try expectArrayArgs(args, env, 1, "vector", "ctor");
            const vals = (try expectNumberArrays(env.allocator, arg, "vector", "ctor"))[0];
            break :blk vals;
        },

        // Vector can be created out of an array and a size val (dim<=4)
        // Vec2 can be created out of 2 numbers (checked first)
        2 => {},

        // Vec3 can be created out of 3 numbers
        3 => {},

        // Vec4 can be created out of 4 numbers
        4 => {},

        else => {
            try writer_err.print("vector(args..) expects a maximum of 4 arguments but got {d}\n", .{args.len});
            return error.ArgumentCountMismatch;
        },
    };

    // Repack vec into an arraylist
    const arr = try std.ArrayList(f64).initCapacity(env.allocator, vec.len);
    try arr.appendSlice(vec);

    const wrapped = try env.allocator.create(VectorInstance);
    wrapped.* = .{
        .vector = arr,
    };

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
    type_ptr.* = VECTOR_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}