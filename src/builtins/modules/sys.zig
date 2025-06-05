const std = @import("std");

const ast = @import("../../parser/ast.zig");
const environment = @import("../../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

var sys_env: std.process.EnvMap = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);
    sys_env = std.process.EnvMap.init(allocator);

    try pack(&map, "args", argsHandler);
    try pack(&map, "getenv", getenvHandler);
    try pack(&map, "setenv", setenvHandler);
    try pack(&map, "unsetenv", unsetenvHandler);

    return .{
        .object = map,
    };
}

fn argsHandler(allocator: std.mem.Allocator, _: []const *ast.Expr, _: *Environment) !Value {
    const args = try std.process.argsAlloc(allocator);
    var array = std.ArrayList(Value).init(allocator);
    for (args) |arg| {
        try array.append(
            .{
                .string = arg,
            },
        );
    }
    return .{
        .array = array,
    };
}

fn getenvHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }
    const key = try eval.evalExpr(args[0], env);
    if (key != .string) {
        return error.TypeMismatch;
    }

    const val = sys_env.get(key.string) orelse return .nil;
    return .{
        .string = val,
    };
}

fn setenvHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }
    const key = try eval.evalExpr(args[0], env);
    const val = try eval.evalExpr(args[1], env);
    if (key != .string or val != .string) {
        return error.TypeMismatch;
    }

    try sys_env.put(key.string, val.string);
    return .nil;
}

fn unsetenvHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }
    const key = try eval.evalExpr(args[0], env);
    if (key != .string) {
        return error.TypeMismatch;
    }

    sys_env.remove(key.string);
    return .nil;
}
