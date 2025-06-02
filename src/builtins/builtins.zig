const std = @import("std");

const ast = @import("../ast/ast.zig");
const environment = @import("../interpreter/environment.zig");
const eval = @import("../interpreter/eval.zig");

const Environment = environment.Environment;
const Value = environment.Value;

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
    .{ .name = "print", .handler = builtinPrint },
    .{ .name = "println", .handler = builtinPrintLn },
    .{ .name = "len", .handler = builtinLen },
};

fn builtinPrint(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const stdout = std.io.getStdOut().writer();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        try stdout.print("{s}", .{val.toString(allocator)});
    }
    return Value.nil;
}

fn builtinPrintLn(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const stdout = std.io.getStdOut().writer();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        try stdout.print("{s}\n", .{val.toString(allocator)});
    }
    return Value.nil;
}

fn builtinLen(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    _ = allocator;
    if (args.len != 1) return error.ArgumentCountMismatch;
    const val = try eval.evalExpr(args[0], env);
    return switch (val) {
        .array => |a| Value{
            .number = @floatFromInt(a.items.len),
        },
        .string => |s| Value{
            .number = @floatFromInt(s.len),
        },
        else => error.TypeMismatch,
    };
}

// === Builtin Modules ===
const fs_mod = @import("fs.zig");
const time_mod = @import("time.zig");
const math_mod = @import("math.zig");

const BuiltinModuleHandler = *const fn (
    allocator: std.mem.Allocator,
) anyerror!Value;

const BuiltinModule = struct {
    name: []const u8,
    loader: BuiltinModuleHandler,
};

pub const builtin_modules = [_]BuiltinModule{
    .{ .name = "fs", .loader = fs_mod.load },
    .{ .name = "time", .loader = time_mod.load },
    .{ .name = "math", .loader = math_mod.load },
};