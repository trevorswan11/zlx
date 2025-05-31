const std = @import("std");

const environment = @import("environment.zig");
const eval = @import("eval.zig");
const ast = @import("../ast/ast.zig");

const Environment = environment.Environment;
const Value = environment.Value;

const BuiltinHandler = *const fn (
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
) anyerror!Value;

const Builtin = struct {
    name: []const u8,
    handler: BuiltinHandler,
};

pub const builtins = [_]Builtin{
    .{ .name = "print", .handler = builtinPrint },
    .{ .name = "len", .handler = builtinLen },
};

fn builtinPrint(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        std.debug.print("{s}\n", .{val.toString(allocator)});
    }
    return Value.nil;
}

fn builtinLen(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    _ = allocator;
    if (args.len != 1) return error.ArgumentCountMismatch;
    const val = try eval.evalExpr(args[0], env);
    return switch (val) {
        .array => |a| Value{ .number = @floatFromInt(a.items.len) },
        .string => |s| Value{ .number = @floatFromInt(s.len) },
        else => error.TypeMismatch,
    };
}
