const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

fn expectStringArg(args: []const *ast.Expr, env: *Environment) ![]const u8 {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    if (val != .string) {
        return error.TypeMismatch;
    }
    return val.string;
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "upper", upperHandler);
    try pack(&map, "lower", lowerHandler);
    try pack(&map, "slice", sliceHandler);
    try pack(&map, "find", findHandler);
    try pack(&map, "replace", replaceHandler);
    try pack(&map, "split", splitHandler);
    try pack(&map, "trim", trimHandler);

    return .{
        .object = map,
    };
}

fn upperHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const s = try expectStringArg(args, env);
    const upper = try std.ascii.allocUpperString(allocator, s);
    return .{
        .string = upper,
    };
}

fn lowerHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const s = try expectStringArg(args, env);
    const lower = try std.ascii.allocLowerString(allocator, s);
    return .{
        .string = lower,
    };
}

fn sliceHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    if (args.len != 3) {
        return error.ArgumentCountMismatch;
    }

    const str = try eval.evalExpr(args[0], env);
    const start = try eval.evalExpr(args[1], env);
    const end = try eval.evalExpr(args[2], env);

    if (str != .string or start != .number or end != .number) {
        return error.TypeMismatch;
    }

    const s = @min(@as(usize, @intFromFloat(start.number)), @as(usize, @intCast(str.string.len)));
    const e = @min(@as(usize, @intFromFloat(end.number)), @as(usize, @intCast(str.string.len)));

    const slice = try allocator.dupe(u8, str.string[s..e]);
    return .{
        .string = slice,
    };
}

fn findHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const haystack = try eval.evalExpr(args[0], env);
    const needle = try eval.evalExpr(args[1], env);

    if (haystack != .string or needle != .string) {
        return error.TypeMismatch;
    }

    if (std.mem.indexOf(u8, haystack.string, needle.string)) |idx| {
        return .{
            .number = @floatFromInt(idx),
        };
    } else {
        return .nil;
    }
}

fn replaceHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    if (args.len != 3) {
        return error.ArgumentCountMismatch;
    }

    const haystack = try eval.evalExpr(args[0], env);
    const needle = try eval.evalExpr(args[1], env);
    const replacement = try eval.evalExpr(args[2], env);

    if (haystack != .string or needle != .string or replacement != .string) {
        return error.TypeMismatch;
    }

    const result = try std.mem.replaceOwned(u8, allocator, haystack.string, needle.string, replacement.string);
    return .{
        .string = result,
    };
}

fn splitHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const input = try eval.evalExpr(args[0], env);
    const delim = try eval.evalExpr(args[1], env);

    if (input != .string or delim != .string) {
        return error.TypeMismatch;
    }

    var iter = std.mem.splitAny(u8, input.string, delim.string);
    var list = std.ArrayList(Value).init(allocator);

    while (iter.next()) |part| {
        const copy = try allocator.dupe(u8, part);
        try list.append(
            .{
                .string = copy,
            },
        );
    }

    return Value{
        .array = list,
    };
}

fn trimHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const s = try expectStringArg(args, env);
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    return .{
        .string = try allocator.dupe(u8, trimmed),
    };
}
