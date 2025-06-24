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

fn expectArrayRef(args: []const *ast.Expr, env: *Environment) !*std.ArrayList(Value) {
    const writer_err = driver.getWriterErr();
    if (args.len < 1) {
        try writer_err.print("array module: expected at least one argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .reference or val.reference.* != .array) {
        try writer_err.print("array module: expression evaluation returned a value that is not a reference to an array\n", .{});
        if (val == .reference) {
            try writer_err.print("  Found a reference to a(n) {s}\n", .{@tagName(val)});
        } else {
            try writer_err.print("  Found a(n) {s}\n", .{@tagName(val.deref())});
        }
        return error.TypeMismatch;
    }

    return &val.reference.*.array;
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "push", pushHandler);
    try pack(&map, "pop", popHandler);
    try pack(&map, "insert", insertHandler);
    try pack(&map, "remove", removeHandler);
    try pack(&map, "clear", clearHandler);
    try pack(&map, "get", getHandler);
    try pack(&map, "set", setHandler);
    try pack(&map, "slice", sliceHandler);
    try pack(&map, "join", joinHandler);

    return .{
        .object = map,
    };
}

fn pushHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    var array = try expectArrayRef(args, env);
    if (args.len != 2) {
        try writer_err.print("array.push(arr, value) expects exactly two arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const value = try eval.evalExpr(args[1], env);
    try array.append(value);
    return .nil;
}

fn popHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    var array = try expectArrayRef(args, env);
    if (array.items.len == 0) {
        try writer_err.print("array.pop(arr) requires the input array to have at least one item\n", .{});
        return error.OutOfBounds;
    }

    return array.pop() orelse .nil;
}

fn insertHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    var array = try expectArrayRef(args, env);
    if (args.len != 3) {
        try writer_err.print("array.insert(arr, index, value) expects exactly three arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    const value = try eval.evalExpr(args[2], env);
    if (index_val != .number) {
        try writer_err.print("Array index value must be a number, got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const index: usize = @intFromFloat(index_val.number);
    if (index > array.items.len) {
        try writer_err.print("Index {d} is out of bounds for array of length {d}\n", .{ index, array.items.len });
        return error.OutOfBounds;
    }

    try array.insert(index, value);
    return .nil;
}

fn removeHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    var array = try expectArrayRef(args, env);
    if (args.len != 2) {
        try writer_err.print("array.remove(arr, index) expects exactly two arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    if (index_val != .number) {
        try writer_err.print("Array index value must be a number, got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const index: usize = @intFromFloat(index_val.number);
    if (index >= array.items.len) {
        try writer_err.print("Index {d} is out of bounds for array of length {d}\n", .{ index, array.items.len });
        return error.OutOfBounds;
    }

    return array.orderedRemove(index);
}

fn clearHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var array = try expectArrayRef(args, env);
    array.clearRetainingCapacity();
    return .nil;
}

fn getHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("array.get(...) expects exactly two arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    var val = try eval.evalExpr(args[0], env);
    if (val != .array or (val == .reference and val.reference.* != .array)) {
        try writer_err.print("array.get(...) requires the first argument to be an array or a reference to one\n", .{});
        return error.TypeMismatch;
    }
    val = if (val == .reference) val.deref() else val;

    const index_val = try eval.evalExpr(args[1], env);
    if (index_val != .number) {
        try writer_err.print("Array index value must be a number, got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const index: usize = @intFromFloat(index_val.number);
    if (index >= val.array.items.len) {
        try writer_err.print("Index {d} is out of bounds for array of length {d}\n", .{ index, val.array.items.len });
        return error.OutOfBounds;
    }

    return val.array.items[index];
}

fn setHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("array.set(...) expects exactly two arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const ref_val = try eval.evalExpr(args[0], env);
    if (ref_val != .reference or ref_val.reference.* != .array) {
        try writer_err.print("Expression evaluation returned a value that is not a reference to an array, got a(n) {s}\n", .{@tagName(ref_val)});
        return error.TypeMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    if (index_val != .number) {
        try writer_err.print("Array index value must be a number, got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const value = try eval.evalExpr(args[2], env);
    const index: usize = @intFromFloat(index_val.number);

    var array = &ref_val.reference.*.array;
    if (index >= array.items.len) {
        try writer_err.print("Index {d} is out of bounds for array of length {d}\n", .{ index, array.items.len });
        return error.OutOfBounds;
    }

    array.items[index] = value;
    return .nil;
}

fn sliceHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len < 2 or args.len > 3) {
        try writer_err.print("array.slice(...) expects between two and three arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    var val = try eval.evalExpr(args[0], env);
    if (val != .array or (val == .reference and val.reference.* != .array)) {
        try writer_err.print("array.alice(...) requires the first argument to be an array or a reference to one, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }
    val = if (val == .reference) val.deref() else val;

    const start: usize = @intFromFloat((try eval.evalExpr(args[1], env)).number);
    const end: usize = if (args.len == 3) @intFromFloat((try eval.evalExpr(args[2], env)).number) else val.array.items.len;

    if (start < 0 or end > val.array.items.len or start > end) {
        try writer_err.print("Index out of bounds for array of length {d}\n", .{val.array.items.len});
        return error.OutOfBounds;
    }

    var new_array = std.ArrayList(Value).init(allocator);
    for (start..end) |i| {
        try new_array.append(val.array.items[i]);
    }

    return .{
        .array = new_array,
    };
}

fn joinHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("array.join(arr, delim) expects exactly two arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    var val = try eval.evalExpr(args[0], env);
    if (val != .array and !(val == .reference and val.reference.* == .array)) {
        try writer_err.print("array.join(arr, delim) requires the first argument to be an array or reference to an array\n", .{});
        return error.TypeMismatch;
    }

    val = if (val == .reference) val.deref() else val;

    const delim_val = try eval.evalExpr(args[1], env);
    if (delim_val != .string) {
        try writer_err.print("array.join(arr, delim) requires the delimiter to be a string\n", .{});
        return error.TypeMismatch;
    }

    const delim = delim_val.string;

    const items = val.array.items;
    var output = std.ArrayList(u8).init(allocator);
    const writer = output.writer();

    for (items, 0..) |item, i| {
        switch (item) {
            .string => try writer.print("{s}", .{item.string}),
            .number => try writer.print("{}", .{item.number}),
            .boolean => try writer.print("{}", .{item.boolean}),
            else => try writer.print("{s}", .{try item.toString(allocator)}),
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
        \\let a = ref([1, 2, 3]);
        \\array.push(a, 4);
        \\println(a);  // Expect: [1, 2, 3, 4]
        \\println(array.pop(a));  // Expect: 4
        \\println(a);             // Expect: [1, 2, 3]
        \\array.insert(a, 1, 99);
        \\println(a);  // Expect: [1, 99, 2, 3]
        \\println(array.remove(a, 2)); // Expect: 2
        \\println(a);                  // Expect: [1, 99, 3]
        \\array.clear(a);
        \\println(a);  // Expect: []
        \\
        \\let b = [10, 20, 30];
        \\println(array.get(b, 1));  // Expect: 20
        \\
        \\let c = ref(b);
        \\array.set(c, 1, 99);
        \\println(c);  // Expect: [10, 99, 30]
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
        \\References Val: ["1", "2", "3", "4"]
        \\4
        \\References Val: ["1", "2", "3"]
        \\References Val: ["1", "99", "2", "3"]
        \\2
        \\References Val: ["1", "99", "3"]
        \\References Val: []
        \\20
        \\References Val: ["10", "99", "30"]
        \\["2", "3", "4"]
        \\a-b-c
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
