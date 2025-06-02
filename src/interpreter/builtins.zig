const std = @import("std");

const environment = @import("environment.zig");
const eval = @import("eval.zig");
const ast = @import("../ast/ast.zig");

const Environment = environment.Environment;
const Value = environment.Value;

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
    .{ .name = "len", .handler = builtinLen },
};

fn builtinPrint(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
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

const BuiltinModuleHandler = *const fn (
    allocator: std.mem.Allocator,
) anyerror!Value;

const BuiltinModule = struct {
    name: []const u8,
    loader: BuiltinModuleHandler,
};

pub const builtin_modules = [_]BuiltinModule{
    .{ .name = "fs", .loader = builtinFsMod },
    .{ .name = "time", .loader = builtinTimeMod },
    .{ .name = "path", .loader = builtinPathMod },
};

fn builtinFsMod(allocator: std.mem.Allocator) !Value {
    _ = allocator;
    return Value.nil;
}

fn builtinTimeMod(allocator: std.mem.Allocator) !Value {
    _ = allocator;
    return Value.nil;
}

fn builtinPathMod(allocator: std.mem.Allocator) !Value {
    _ = allocator;
    return Value.nil;
}
