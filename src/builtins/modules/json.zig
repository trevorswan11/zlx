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

    try pack(&map, "parse", parseHandler);
    try pack(&map, "stringify", stringifyHandler);

    return .{
        .object = map,
    };
}

fn parseHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const str = (try expectStringArgs(args, env, 1, "json", "parse", "str"))[0];
    return try parseJson(env.allocator, str);
}

fn stringifyHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const val = (try expectValues(args, env, 1, "json", "stringify", "value"))[0];
    const str = try stringifyJson(env.allocator, val);
    return .{
        .string = str,
    };
}

fn parseJson(allocator: std.mem.Allocator, text: []const u8) !Value {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();

    return try fromJson(allocator, parsed.value);
}

fn stringifyJson(allocator: std.mem.Allocator, value: Value) ![]u8 {
    const json_value = try toJson(allocator, value);
    return try std.json.stringifyAlloc(allocator, json_value, .{ .whitespace = .minified });
}

fn fromJson(allocator: std.mem.Allocator, j: std.json.Value) !Value {
    return switch (j) {
        .null => .{ .nil = {} },
        .bool => |b| .{
            .boolean = b,
        },
        .integer => |n| .{
            .number = @floatFromInt(n),
        },
        .float => |f| .{
            .number = f,
        },
        .string, .number_string => |s| .{
            .string = try allocator.dupe(u8, s),
        },
        .array => |arr| {
            var out = try std.ArrayList(Value).initCapacity(allocator, arr.items.len);
            for (arr.items) |item| {
                try out.append(try fromJson(allocator, item));
            }
            return .{
                .array = out,
            };
        },
        .object => |obj| {
            var map = std.StringHashMap(Value).init(allocator);
            var itr = obj.iterator();
            while (itr.next()) |entry| {
                const k = try allocator.dupe(u8, entry.key_ptr.*);
                const v = try fromJson(allocator, entry.value_ptr.*);
                try map.put(k, v);
            }
            return .{
                .object = map,
            };
        },
    };
}

fn toJson(allocator: std.mem.Allocator, val: Value) !std.json.Value {
    const writer_err = driver.getWriterErr();
    return switch (val) {
        .nil => std.json.Value{
            .null = {},
        },
        .boolean => |b| std.json.Value{
            .bool = b,
        },
        .number => |n| std.json.Value{
            .float = n,
        },
        .string => |s| std.json.Value{
            .string = try allocator.dupe(u8, s),
        },
        .array => |arr| {
            var json_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try json_arr.append(try toJson(allocator, item));
            }
            return .{
                .array = json_arr,
            };
        },
        .object => |map| {
            var json_obj = std.json.ObjectMap.init(allocator);
            var it = map.iterator();
            while (it.next()) |entry| {
                const k = entry.key_ptr.*;
                const v = try toJson(allocator, entry.value_ptr.*);
                try json_obj.put(try allocator.dupe(u8, k), v);
            }
            return .{
                .object = json_obj,
            };
        },
        else => {
            try writer_err.print("cannot convert value type {s} to json\n", .{@tagName(val)});
            return error.UnsupportedJsonType;
        },
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "json_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriters(writer);

    const source =
        \\import json;
        \\
        \\let obj = json.parse(```{"x": 1, "y": [true, null]}```);
        \\println(obj);
        \\println(obj["x"]);
        \\println(obj["y"][0]);
        \\println(obj["y"][1]);
        \\let out = json.stringify(obj);
        \\println(out);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\[obj]: {
        \\ x: 1
        \\ y: ["true", "nil"]
        \\}
        \\1
        \\true
        \\nil
        \\{"x":1e0,"y":[true,null]}
        \\
    ;

    try testing.expectEqualStrings(expected, output_buffer.items);
}
