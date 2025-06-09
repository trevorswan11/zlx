const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const eval = @import("../interpreter/eval.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn print(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterOut();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try writer.print("{s}", .{str});
    }
    return .nil;
}

pub fn println(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterOut();
    if (args.len == 0) {
        try writer.print("\n", .{});
    }

    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try writer.print("{s}\n", .{str});
    }
    return .nil;
}

pub fn len(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterErr();
    if (args.len != 1) {
        try writer.print("len(...): expected exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    return switch (val) {
        .array => |a| .{
            .number = @floatFromInt(a.items.len),
        },
        .string => |s| .{
            .number = @floatFromInt(s.len),
        },
        else => {
            try writer.print("len(...): only operates on strings and arrays\n", .{});
            try writer.print("  Found: {s}\n", .{try val.toString(env.allocator)});
            return error.TypeMismatch;
        },
    };
}

pub fn ref(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterErr();

    if (args.len != 1) {
        try writer.print("ref(...): expected exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);

    if (val == .reference) {
        return val;
    }

    const heap_val = try env.allocator.create(Value);
    heap_val.* = val;

    return .{
        .reference = heap_val,
    };
}

pub fn range(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterErr();

    if (args.len == 2) {
        try writer.print("range(...): expected 3 arguments (start, end, step), got {d}\n", .{args.len});
        try writer.print("  Consider using 'start..end' syntax\n", .{});
        return error.ArgumentCountMismatch;
    } else if (args.len != 3) {
        try writer.print("range(...): expected 3 arguments (start, end, step), got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);
    const c = try eval.evalExpr(args[2], env);

    if (a != .number or b != .number or c != .number) {
        try writer.print("range(...): all arguments must be numbers\n", .{});
        try writer.print("  Start = {s}\n", .{try a.toString(env.allocator)});
        try writer.print("  End = {s}\n", .{try b.toString(env.allocator)});
        try writer.print("  Step = {s}\n", .{try c.toString(env.allocator)});
        return error.TypeMismatch;
    }

    const start: i64 = @intFromFloat(a.number);
    const end: i64 = @intFromFloat(b.number);
    const step: i64 = @intFromFloat(c.number);

    if (step == 0) {
        try writer.print("range(...): step cannot be zero\n", .{});
        return error.InvalidStep;
    }

    var result = std.ArrayList(Value).init(allocator);
    if (step > 0) {
        var i = start;
        while (i < end) : (i += step) {
            try result.append(.{ .number = @floatFromInt(i) });
        }
    } else {
        var i = start;
        while (i > end) : (i += step) {
            try result.append(.{ .number = @floatFromInt(i) });
        }
    }

    return .{
        .array = result,
    };
}

pub fn to_string(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterErr();

    if (args.len != 1) {
        try writer.print("to_string(...) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    const str = try val.toString(allocator);
    return .{
        .string = str,
    };
}

pub fn to_number(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer = eval.getWriterErr();

    if (args.len != 1) {
        try writer.print("to_number(...) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .string) {
        try writer.print("to_number(...) expects a string argument\n", .{});
        try writer.print("  Found: {s}\n", .{try val.toString(env.allocator)});
        return error.TypeMismatch;
    }

    const parsed = std.fmt.parseFloat(f64, val.string) catch {
        try writer.print("to_number(...) failed to parse input: \"{s}\"\n", .{val.string});
        return error.ParseFailure;
    };

    return .{
        .number = parsed,
    };
}

// === TESTING ===

const testing = @import("../testing/testing.zig");

test "core_builtins" {
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
        \\let s = "hello";
        \\let a = [1, 2, 3, 4];
        \\
        \\// Test len on string and array
        \\println(len(s)); // 5
        \\println(len(a)); // 4
        \\
        \\// Test ref
        \\let r = ref([9, 8]);
        \\println(r); // References Val: ["9", "8"]
        \\
        \\// Test range
        \\println(range(0, 5, 1));    // [0, 1, 2, 3, 4]
        \\println(range(5, 0, -2));   // [5, 3, 1]
        \\println(range(0, 1, 3));    // [0]
        \\
        \\// Test print vs println
        \\print("no newline"); print(" +"); println("print"); // no newline +print\n
        \\print("a single ", "print statement: ", 3);
        \\println();
        \\
        \\// Test to_string and to_number
        \\println(to_string(42));        // "42"
        \\println(to_string("hi"));      // "hi"
        \\println(to_number("3.1415"));  // 3.1415
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\5
        \\4
        \\References Val: ["9", "8"]
        \\["0", "1", "2", "3", "4"]
        \\["5", "3", "1"]
        \\["0"]
        \\no newline +print
        \\a single print statement: 3
        \\42
        \\hi
        \\3.1415
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
