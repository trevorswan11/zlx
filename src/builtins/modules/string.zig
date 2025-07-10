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
const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "upper", upperHandler);
    try pack(&map, "lower", lowerHandler);
    try pack(&map, "slice", sliceHandler);
    try pack(&map, "find", findHandler);
    try pack(&map, "replace", replaceHandler);
    try pack(&map, "split", splitHandler);
    try pack(&map, "ltrim", ltrimHandler);
    try pack(&map, "rtrim", rtrimHandler);
    try pack(&map, "trim", trimHandler);
    try pack(&map, "contains", containsHandler);
    try pack(&map, "starts_with", startsWithHandler);
    try pack(&map, "ends_with", endsWithHandler);

    return .{
        .object = map,
    };
}

fn upperHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const s = (try expectStringArgs(args, env, 1, "string", "upper", "str"))[0];
    const upper = try std.ascii.allocUpperString(env.allocator, s);
    return .{
        .string = upper,
    };
}

fn lowerHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const s = (try expectStringArgs(args, env, 1, "string", "lower", "str"))[0];
    const lower = try std.ascii.allocLowerString(env.allocator, s);
    return .{
        .string = lower,
    };
}

fn sliceHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();

    const str = (try expectStringArgs(args[0..1], env, 1, "string", "slice", "str, start, end"))[0];
    const parts = try expectNumberArgs(args[1..], env, 2, "string", "slice", "str, start, end");
    const start = parts[0];
    const end = parts[1];

    const s = @min(@max(@as(usize, @intFromFloat(start)), @as(usize, 0)), @as(usize, @intCast(str.len)));
    const e = @min(@max(@as(usize, @intFromFloat(end)), @as(usize, 0)), @as(usize, @intCast(str.len)));

    if (s > e) {
        try writer_err.print("string.slice(str, start, end): start ({d}) cannot be greater than end ({d})\n", .{ s, e });
        return error.StringSliceStartGreaterThanEnd;
    }

    const slice = try env.allocator.dupe(u8, str[s..e]);
    return .{
        .string = slice,
    };
}

fn findHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "string", "find", "str, pattern");
    const haystack = parts[0];
    const needle = parts[1];

    if (std.mem.indexOf(u8, haystack, needle)) |idx| {
        return .{
            .number = @floatFromInt(idx),
        };
    } else {
        return .nil;
    }
}

fn containsHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "string", "contains", "str, needle");
    const haystack = parts[0];
    const needle = parts[1];

    return .{
        .boolean = std.mem.indexOf(u8, haystack, needle) != null,
    };
}

fn replaceHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 3, "string", "replace", "str, needle, haystack");
    const haystack = parts[0];
    const needle = parts[1];
    const replacement = parts[2];

    const result = try std.mem.replaceOwned(u8, env.allocator, haystack, needle, replacement);
    return .{
        .string = result,
    };
}

fn splitHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "string", "split", "str, delimiter");
    const input = parts[0];
    const delim = parts[1];

    var iter = std.mem.splitAny(u8, input, delim);
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

fn ltrimHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const s = (try expectStringArgs(args, env, 1, "string", "ltrim", "str"))[0];
    const trimmed = std.mem.trimLeft(u8, s, " \t\n\r");
    return .{
        .string = try env.allocator.dupe(u8, trimmed),
    };
}

fn rtrimHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const s = (try expectStringArgs(args, env, 1, "string", "rtrim", "str"))[0];
    const trimmed = std.mem.trimRight(u8, s, " \t\n\r");
    return .{
        .string = try env.allocator.dupe(u8, trimmed),
    };
}

fn trimHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const s = (try expectStringArgs(args, env, 1, "string", "trim", "str"))[0];
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    return .{
        .string = try env.allocator.dupe(u8, trimmed),
    };
}

fn startsWithHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectStringArgs(args, env, 2, "string", "starts_with", "str, prefix");
    const str = parts[0];
    const prefix = parts[1];

    return .{
        .boolean = std.mem.startsWith(u8, str, prefix),
    };
}

fn endsWithHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectStringArgs(args, env, 2, "string", "ends_with", "str, suffix");
    const str = parts[0];
    const suffix = parts[1];

    return .{
        .boolean = std.mem.endsWith(u8, str, suffix),
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
