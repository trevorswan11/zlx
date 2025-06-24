const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;
const expectStringArgs = builtins.expectStringArgs;

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
    try pack(&map, "starts_with", startsWithHandler);
    try pack(&map, "ends_with", endsWithHandler);

    return .{
        .object = map,
    };
}

fn upperHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const s = (try expectStringArgs(args, env, 1, "string", "upper"))[0];
    const upper = try std.ascii.allocUpperString(env.allocator, s);
    return .{
        .string = upper,
    };
}

fn lowerHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const s = (try expectStringArgs(args, env, 1, "string", "lower"))[0];
    const lower = try std.ascii.allocLowerString(env.allocator, s);
    return .{
        .string = lower,
    };
}

fn sliceHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("string.slice(str, start, end) expects 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const str = try eval.evalExpr(args[0], env);
    const start = try eval.evalExpr(args[1], env);
    const end = try eval.evalExpr(args[2], env);

    if (str != .string or start != .number or end != .number) {
        try writer_err.print("string.slice(str, start, end) requires a string and two numbers\n", .{});
        try writer_err.print("  Got: str = {s}, start = {s}, end = {s}\n", .{
            try str.toString(env.allocator),
            try start.toString(env.allocator),
            try end.toString(env.allocator),
        });
        return error.TypeMismatch;
    }

    const s = @min(@as(usize, @intFromFloat(start.number)), @as(usize, @intCast(str.string.len)));
    const e = @min(@as(usize, @intFromFloat(end.number)), @as(usize, @intCast(str.string.len)));

    const slice = try env.allocator.dupe(u8, str.string[s..e]);
    return .{
        .string = slice,
    };
}

fn findHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("string.find(str, pattern) expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const haystack = try eval.evalExpr(args[0], env);
    const needle = try eval.evalExpr(args[1], env);

    if (haystack != .string or needle != .string) {
        try writer_err.print("string.find(str, pattern) expects two strings\n", .{});
        try writer_err.print("  Left: {s}\n", .{try haystack.toString(env.allocator)});
        try writer_err.print("  Right: {s}\n", .{try needle.toString(env.allocator)});
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

fn containsHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("string.contains(str, pattern) expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const haystack = try eval.evalExpr(args[0], env);
    const needle = try eval.evalExpr(args[1], env);

    if (haystack != .string or needle != .string) {
        try writer_err.print("string.contains(str, pattern) expects two strings\n", .{});
        try writer_err.print("  Left: {s}\n", .{try haystack.toString(env.allocator)});
        try writer_err.print("  Right: {s}\n", .{try needle.toString(env.allocator)});
        return error.TypeMismatch;
    }

    return .{
        .boolean = std.mem.indexOf(u8, haystack.string, needle.string) != null,
    };
}

fn replaceHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("string.replace(str, original, replacement) expects 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const haystack = try eval.evalExpr(args[0], env);
    const needle = try eval.evalExpr(args[1], env);
    const replacement = try eval.evalExpr(args[2], env);

    if (haystack != .string or needle != .string or replacement != .string) {
        try writer_err.print("string.replace(str, original, replacement) expects three string arguments\n", .{});
        try writer_err.print("  Haystack: {s}\n", .{try haystack.toString(env.allocator)});
        try writer_err.print("  Needle: {s}\n", .{try needle.toString(env.allocator)});
        try writer_err.print("  Replacement: {s}\n", .{try replacement.toString(env.allocator)});
        return error.TypeMismatch;
    }

    const result = try std.mem.replaceOwned(u8, env.allocator, haystack.string, needle.string, replacement.string);
    return .{
        .string = result,
    };
}

fn splitHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("string.split(str, delimiter) expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const input = try eval.evalExpr(args[0], env);
    const delim = try eval.evalExpr(args[1], env);

    if (input != .string or delim != .string) {
        try writer_err.print("string.split(str, delimiter) expects two string arguments\n", .{});
        try writer_err.print("  Input: {s}\n", .{try input.toString(env.allocator)});
        try writer_err.print("  Delimiter: {s}\n", .{try delim.toString(env.allocator)});
        return error.TypeMismatch;
    }

    var iter = std.mem.splitAny(u8, input.string, delim.string);
    var list = std.ArrayList(Value).init(env.allocator);

    while (iter.next()) |part| {
        const copy = try env.allocator.dupe(u8, part);
        try list.append(
            .{
                .string = copy,
            },
        );
    }

    return .{
        .array = list,
    };
}

fn trimHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const s = (try expectStringArgs(args, env, 1, "string", "trim"))[0];
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    return .{
        .string = try env.allocator.dupe(u8, trimmed),
    };
}

fn startsWithHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("string.starts_with(str, prefix) expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const str = try eval.evalExpr(args[0], env);
    const prefix = try eval.evalExpr(args[1], env);

    if (str != .string or prefix != .string) {
        try writer_err.print("string.starts_with expects two string arguments\n", .{});
        try writer_err.print("  str = {s}, prefix = {s}\n", .{
            try str.toString(env.allocator),
            try prefix.toString(env.allocator),
        });
        return error.TypeMismatch;
    }

    return .{
        .boolean = std.mem.startsWith(u8, str.string, prefix.string),
    };
}

fn endsWithHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("string.ends_with(str, suffix) expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const str = try eval.evalExpr(args[0], env);
    const suffix = try eval.evalExpr(args[1], env);

    if (str != .string or suffix != .string) {
        try writer_err.print("string.ends_with expects two string arguments\n", .{});
        try writer_err.print("  str = {s}, suffix = {s}\n", .{
            try str.toString(env.allocator),
            try suffix.toString(env.allocator),
        });
        return error.TypeMismatch;
    }

    return .{
        .boolean = std.mem.endsWith(u8, str.string, suffix.string),
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
    driver.setWriters(writer);

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
        \\// Test starts_with and ends_with
        \\println(string.starts_with("ZigLang", "Zig")); // true
        \\println(string.starts_with("ZigLang", "Lang")); // false
        \\println(string.ends_with("ZigLang", "Lang")); // true
        \\println(string.ends_with("ZigLang", "Zig")); // false
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
        \\true
        \\false
        \\true
        \\false
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
