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
    try pack(&map, "contains", containsHandler);

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

fn containsHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const haystack = try eval.evalExpr(args[0], env);
    const needle = try eval.evalExpr(args[1], env);

    if (haystack != .string or needle != .string) {
        return error.TypeMismatch;
    }

    return Value{
        .boolean = std.mem.indexOf(u8, haystack.string, needle.string) != null,
    };
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

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "string_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    eval.setWriters(writer);

    const source =
        \\import string;
        \\
        \\// Test slice
        \\println(string.slice("Hello, world!", 0, 5)); // "Hello"
        \\println(string.slice("ZigLang", 3, 7));       // "Lang"
        \\
        \\// Test find
        \\println(string.find("Hello, world!", "world")); // 7
        \\println(string.find("abcdef", "x"));            // nil
        \\
        \\// Test replace
        \\println(string.replace("a-b-c", "-", ":"));     // "a:b:c"
        \\println(string.replace("123123", "12", "X"));   // "X3X3"
        \\
        \\// Test split
        \\let parts = string.split("one,two,three", ",");
        \\println(parts); // ["one", "two", "three"]
        \\
        \\// Test trim
        \\println(string.trim("   zig   ")); // "zig"
        \\
        \\// Test lower
        \\println(string.lower("HeLLo")); // "hello"
        \\
        \\// Test upper
        \\println(string.upper("ZigLang")); // "ZIGLANG"
        \\
        \\// Test contains
        \\println(string.contains("hello world", "world")); // true
        \\println(string.contains("zig", "Z"));             // false
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\Hello
        \\Lang
        \\7
        \\nil
        \\a:b:c
        \\X3X3
        \\["one", "two", "three"]
        \\zig
        \\hello
        \\ZIGLANG
        \\true
        \\false
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
