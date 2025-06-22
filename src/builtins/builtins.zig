const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const eval = @import("../interpreter/eval.zig");
const driver = @import("../utils/driver.zig");
const fns = @import("fns.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn pack(map: *std.StringHashMap(Value), name: []const u8, builtin: BuiltinModuleHandler) !void {
    try map.put(
        name,
        .{
            .builtin = builtin,
        },
    );
}

pub fn expectStringArgs(
    args: []const *ast.Expr,
    env: *Environment,
    count: usize,
    module_name: []const u8,
    func_name: []const u8,
) ![]const []const u8 {
    const writer_err = driver.getWriterErr();

    if (args.len != count) {
        try writer_err.print("{s} module: {s} expected {d} argument(s), got {d}\n", .{ module_name, func_name, count, args.len });
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList([]const u8).init(env.allocator);
    defer result.deinit();

    for (args, 0..) |arg, idx| {
        const val = try eval.evalExpr(arg, env);
        if (val != .string) {
            try writer_err.print("{s} module: {s} expected a string, got a {s} @ arg {d}\n", .{ module_name, func_name, @tagName(val), idx });
            return error.TypeMismatch;
        }
        try result.append(val.string);
    }

    return try result.toOwnedSlice();
}

// === Builtin Functions ===

const BuiltinFnHandler = *const fn (
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
) anyerror!Value;

const BuiltinFn = struct {
    name: []const u8,
    handler: BuiltinFnHandler,
};

pub const builtin_fns = [_]BuiltinFn{
    .{
        .name = "print",
        .handler = fns.print,
    },
    .{
        .name = "println",
        .handler = fns.println,
    },
    .{
        .name = "len",
        .handler = fns.len,
    },
    .{
        .name = "ref",
        .handler = fns.ref,
    },
    .{
        .name = "deref",
        .handler = fns.deref,
    },
    .{
        .name = "detype",
        .handler = fns.detype,
    },
    .{
        .name = "range",
        .handler = fns.range,
    },
    .{
        .name = "to_string",
        .handler = fns.to_string,
    },
    .{
        .name = "to_number",
        .handler = fns.to_number,
    },
    .{
        .name = "to_bool",
        .handler = fns.to_bool,
    },
    .{
        .name = "to_ascii",
        .handler = fns.to_ascii,
    },
    .{
        .name = "from_ascii",
        .handler = fns.from_ascii,
    },
    .{
        .name = "format",
        .handler = fns.format,
    },
};

// === Builtin Modules ===

const BuiltinModuleLoader = *const fn (
    allocator: std.mem.Allocator,
) anyerror!Value;

pub const BuiltinModuleHandler = *const fn (
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
) anyerror!Value;

const BuiltinModule = struct {
    name: []const u8,
    loader: BuiltinModuleLoader,
};

pub const builtin_modules = [_]BuiltinModule{
    // Modules
    .{
        .name = "fs",
        .loader = @import("modules/fs.zig").load,
    },
    .{
        .name = "time",
        .loader = @import("modules/time.zig").load,
    },
    .{
        .name = "math",
        .loader = @import("modules/math.zig").load,
    },
    .{
        .name = "random",
        .loader = @import("modules/random.zig").load,
    },
    .{
        .name = "string",
        .loader = @import("modules/string.zig").load,
    },
    .{
        .name = "sys",
        .loader = @import("modules/sys.zig").load,
    },
    .{
        .name = "debug",
        .loader = @import("modules/debug.zig").load,
    },
    .{
        .name = "array",
        .loader = @import("modules/array.zig").load,
    },
    .{
        .name = "path",
        .loader = @import("modules/path.zig").load,
    },
    .{
        .name = "csv",
        .loader = @import("modules/csv.zig").load,
    },
    .{
        .name = "json",
        .loader = @import("modules/json.zig").load,
    },

    // Types
    .{
        .name = "adjacency_list",
        .loader = @import("types/adjacency_list.zig").load,
    },
    .{
        .name = "adjacency_matrix",
        .loader = @import("types/adjacency_matrix.zig").load,
    },
    .{
        .name = "array_list",
        .loader = @import("types/array_list.zig").load,
    },
    .{
        .name = "deque",
        .loader = @import("types/deque.zig").load,
    },
    .{
        .name = "graph",
        .loader = @import("types/graph.zig").load,
    },
    .{
        .name = "map",
        .loader = @import("types/hash_map.zig").load,
    },
    .{
        .name = "set",
        .loader = @import("types/hash_set.zig").load,
    },
    .{
        .name = "linked_list",
        .loader = @import("types/list.zig").load,
    },
    .{
        .name = "heap",
        .loader = @import("types/priority_queue.zig").load,
    },
    .{
        .name = "queue",
        .loader = @import("types/queue.zig").load,
    },
    .{
        .name = "stack",
        .loader = @import("types/stack.zig").load,
    },
    .{
        .name = "treap",
        .loader = @import("types/treap.zig").load,
    },
};

pub fn getStdStructName(value: *Value) ![]const u8 {
    const writer_err = driver.getWriterErr();
    if (value.* != .std_instance) {
        try writer_err.print("Value type {s} does not derive from a standard struct\n", .{@tagName(value.*)});
        return error.IncorrectTarget;
    }
    const instance = value.std_instance;

    if (instance._type.* != .std_struct) {
        try writer_err.print("Instance type {s} does not derive from a standard struct\n", .{@tagName(value.*)});
        return error.IncorrectTarget;
    }
    const result = instance._type.std_struct;
    return result.name;
}
