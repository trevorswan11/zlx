const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const eval = @import("../interpreter/eval.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn print(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterOut();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try writer.print("{s}", .{str});
    }
    return .nil;
}

pub fn println(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterOut();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try writer.print("{s}\n", .{str});
    }
    return .nil;
}

pub fn len(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    return switch (val) {
        .array => |a| .{
            .number = @floatFromInt(a.items.len),
        },
        .string => |s| .{
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

    return .{
        .reference = heap_val,
    };
}

pub fn range(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 3) {
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);
    const c = try eval.evalExpr(args[2], env);

    if (a != .number or b != .number or c != .number) {
        return error.TypeMismatch;
    }

    const start: i64 = @intFromFloat(a.number);
    const end: i64 = @intFromFloat(b.number);
    const step: i64 = @intFromFloat(c.number);

    if (step == 0) {
        return error.InvalidStep;
    }

    var result = std.ArrayList(Value).init(allocator);
    if (step > 0) {
        var i = start;
        while (i < end) : (i += step) {
            try result.append(
                .{
                    .number = @floatFromInt(i),
                },
            );
        }
    } else {
        var i = start;
        while (i > end) : (i += step) {
            try result.append(
                .{
                    .number = @floatFromInt(i),
                },
            );
        }
    }

    return .{
        .array = result,
    };
}
