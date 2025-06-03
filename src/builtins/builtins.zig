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
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try stdout.print("{s}", .{str});
    }
    return .nil;
}

fn builtinPrintLn(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const stdout = std.io.getStdOut().writer();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try stdout.print("{s}\n", .{str});
    }
    return .nil;
}

fn builtinLen(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
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
    .{ .name = "fs", .loader = @import("fs.zig").load },
    .{ .name = "time", .loader = @import("time.zig").load },
    .{ .name = "math", .loader = @import("math.zig").load },
    .{ .name = "random", .loader = @import("random.zig").load },
    .{ .name = "string", .loader = @import("string.zig").load },
    .{ .name = "sys", .loader = @import("sys.zig").load },
};
