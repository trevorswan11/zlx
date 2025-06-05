const std = @import("std");

const ast = @import("../parser/ast.zig");
const environment = @import("../interpreter/environment.zig");
const eval = @import("../interpreter/eval.zig");

const Environment = environment.Environment;
const Value = environment.Value;

pub fn print(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const stdout = std.io.getStdOut().writer();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try stdout.print("{s}", .{str});
    }
    return .nil;
}

pub fn println(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const stdout = std.io.getStdOut().writer();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try stdout.print("{s}\n", .{str});
    }
    return .nil;
}

pub fn len(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }
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

pub fn ref(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);

    // Avoid wrapping a reference again
    if (val == .reference) return val;

    const heap_val = try env.allocator.create(Value);
    heap_val.* = val;

    return Value{
        .reference = heap_val,
    };
}
