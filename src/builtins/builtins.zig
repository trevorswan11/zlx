const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const eval = @import("../interpreter/eval.zig");
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
};
