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

    try pack(&map, "slice", sliceHandler);
    try pack(&map, "join", joinHandler);

    return .{
        .object = map,
    };
}

fn sliceHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len < 2 or args.len > 3) {
        try writer_err.print("array.slice(...) expects between two and three arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const array = (try expectArrayArgs(args[0..1], env, 1, "array", "slice", "arr, start, end"))[0];
    const start: usize = @intFromFloat((try eval.evalExpr(args[1], env)).number);
    const end: usize = if (args.len == 3) @intFromFloat((try eval.evalExpr(args[2], env)).number) else array.items.len;

    if (start < 0 or end > array.items.len or start > end) {
        try writer_err.print("Index out of bounds for array of length {d}\n", .{array.items.len});
        return error.OutOfBounds;
    }

    var new_array = std.ArrayList(Value).init(env.allocator);
    for (start..end) |i| {
        try new_array.append(array.items[i]);
    }

    return .{
        .array = new_array,
    };
}

fn joinHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("array.join(arr, delim) expects exactly two arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const array = (try expectArrayArgs(args[0..1], env, 1, "array", "slice", "arr, start, end"))[0];
    const delim = (try expectStringArgs(args[1..2], env, 1, "array", "join", "arr, delimiter"))[0];

    const items = array.items;
    var output = std.ArrayList(u8).init(env.allocator);
    const writer = output.writer();

    for (items, 0..) |item, i| {
        switch (item) {
            .string => try writer.print("{s}", .{item.string}),
            .number => try writer.print("{d}", .{item.number}),
            .boolean => try writer.print("{any}", .{item.boolean}),
            else => try writer.print("{s}", .{try item.toString(env.allocator)}),
        }

        if (i != items.len - 1) {
            try writer.print("{s}", .{delim});
        }
    }

    return .{
        .string = try output.toOwnedSlice(),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "array_builtin" {
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
        \\import array;
        \\
        \\let d = [1, 2, 3, 4, 5];
        \\let sub = array.slice(d, 1, 4);
        \\println(sub);  // Expect: [2, 3, 4]
        \\let j = array.join(["a", "b", "c"], "-");
        \\println(j);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\["2", "3", "4"]
        \\a-b-c
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
