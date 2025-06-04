const std = @import("std");

const ast = @import("../parser/ast.zig");
const environment = @import("../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("builtins.zig").BuiltinModuleHandler;

fn packHandler(map: *std.StringHashMap(Value), name: []const u8, builtin: BuiltinModuleHandler) !void {
    try map.put(name, Value{ .builtin = builtin });
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try packHandler(&map, "assert", assertHandler);
    try packHandler(&map, "assertEqual", assertEqualHandler);
    try packHandler(&map, "assertNotEqual", assertNotEqualHandler);

    return Value{
        .object = map,
    };
}

fn assertHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const stderr = std.io.getStdErr().writer();
    if (args.len == 0 or args.len > 2) {
        return error.ArgumentCountMismatch;
    }

    const condition_val = try eval.evalExpr(args[0], env);
    if (condition_val != .boolean) {
        return error.TypeMismatch;
    }

    if (!condition_val.boolean) {
        if (args.len == 2) {
            const msg_val = try eval.evalExpr(args[1], env);
            if (msg_val != .string) {
                return error.TypeMismatch;
            }
            try stderr.print("Assertion failed: {s}\n", .{msg_val.string});
        } else {
            try stderr.print("Assertion failed.\n", .{});
        }
        return error.AssertionFailed;
    }

    return .nil;
}

fn assertEqualHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 2) return error.ArgumentCountMismatch;
    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (!a.eql(b)) {
        try stderr.print("Assertion failed: values not equal.\n", .{});
        try stderr.print("Left: {}\n", .{a});
        try stderr.print("Right: {}\n", .{b});
        return error.AssertionFailed;
    }
    return .nil;
}

fn assertNotEqualHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 2) return error.ArgumentCountMismatch;
    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (a.eql(b)) {
        try stderr.print("Assertion failed: values unexpectedly equal.\n", .{});
        try stderr.print("Value: {}\n", .{a});
        return error.AssertionFailed;
    }
    return .nil;
}
