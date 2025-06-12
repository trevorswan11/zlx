const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const driver = @import("../utils/driver.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn print(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_out = driver.getWriterOut();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try writer_out.print("{s}", .{str});
    }
    return .nil;
}

pub fn println(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_out = driver.getWriterOut();
    if (args.len == 0) {
        try writer_out.print("\n", .{});
    }

    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try val.toString(allocator);
        defer allocator.free(str);
        try writer_out.print("{s}\n", .{str});
    }
    return .nil;
}

pub fn len(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("len(...): expected exactly 1 argument, got {d}\n", .{args.len});
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
            try writer_err.print("len(...): only operates on strings and arrays, got a(n) {s}\n", .{@tagName(val)});
            return error.TypeMismatch;
        },
    };
}

pub fn ref(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("ref(...): expected exactly 1 argument, got {d}\n", .{args.len});
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

pub fn deref(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("deref(...): expected exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);

    if (val != .reference) {
        try writer_err.print("deref(...): expected reference, got {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    return val.reference.*;
}

pub fn range(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len == 2) {
        try writer_err.print("range(...): expected 3 arguments (start, end, step), got {d}\n", .{args.len});
        try writer_err.print("  Consider using 'start..end' syntax\n", .{});
        return error.ArgumentCountMismatch;
    } else if (args.len != 3) {
        try writer_err.print("range(...): expected 3 arguments (start, end, step), got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);
    const c = try eval.evalExpr(args[2], env);

    if (a != .number or b != .number or c != .number) {
        try writer_err.print("range(...): all arguments must be numbers\n", .{});
        try writer_err.print("  Start = {s}\n", .{try a.toString(env.allocator)});
        try writer_err.print("  End = {s}\n", .{try b.toString(env.allocator)});
        try writer_err.print("  Step = {s}\n", .{try c.toString(env.allocator)});
        return error.TypeMismatch;
    }

    const start: i64 = @intFromFloat(a.number);
    const end: i64 = @intFromFloat(b.number);
    const step: i64 = @intFromFloat(c.number);

    if (step == 0) {
        try writer_err.print("range(...): step cannot be zero\n", .{});
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
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("to_string(...) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    const str = try val.toString(allocator);
    return .{
        .string = str,
    };
}

pub fn to_number(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("to_number(...) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .string) {
        try writer_err.print("to_number(...) expects a string argument, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    const parsed = std.fmt.parseFloat(f64, val.string) catch {
        try writer_err.print("to_number(...) failed to parse input: \"{s}\"\n", .{val.string});
        return error.ParseFailure;
    };

    return .{
        .number = parsed,
    };
}

pub fn to_bool(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("to_bool(...) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    return .{
        .boolean = coerceBool(val),
    };
}

pub fn coerceBool(val: Value) bool {
    return switch (val) {
        .boolean => val.boolean,
        .number => val.number > 0,
        .string => val.string.len != 0,
        .array => val.array.items.len != 0,
        .reference => coerceBool(val.reference.*),
        .nil => false,
        else => true, // objects, references, functions, etc. will be considered 'truthy'
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
    driver.setWriters(writer);

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
        \\
        \\// Test boolean coercion
        \\println(to_bool(false));         // false
        \\println(to_bool(true));          // true
        \\println(to_bool(0));             // false
        \\println(to_bool(1));             // true
        \\println(to_bool(""));            // false
        \\println(to_bool("hi"));          // true
        \\println(to_bool([]));            // false
        \\println(to_bool([1]));           // true
        \\println(to_bool(nil));           // false
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
        \\false
        \\true
        \\false
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
