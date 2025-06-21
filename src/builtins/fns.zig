const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const driver = @import("../utils/driver.zig");
const builtins = @import("builtins.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

const getStdStructName = builtins.getStdStructName;

pub fn print(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_out = driver.getWriterOut();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try toPrintableString(allocator, val, env);
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
        const str = try toPrintableString(allocator, val, env);
        defer allocator.free(str);
        try writer_out.print("{s}\n", .{str});
    }
    return .nil;
}

fn toPrintableString(allocator: std.mem.Allocator, val: Value, env: *Environment) ![]u8 {
    switch (val) {
        .std_instance => |instance| {
            if (instance._type.std_struct.methods.get("str")) |str_fn| {
                var mut_val = val;
                const result = try str_fn(allocator, &mut_val, &[_]*ast.Expr{}, env);
                return try result.toString(allocator);
            } else {
                return try allocator.dupe(u8, "<std_instance: no .str()>");
            }
        },
        .std_struct => |_| {
            return try allocator.dupe(u8, "<std_struct>");
        },
        else => {
            return try val.toString(allocator);
        },
    }
}

pub fn len(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    var val = try eval.evalExpr(args[0], env);
    switch (val) {
        .std_instance => |instance| {
            if (instance._type.std_struct.methods.get("size")) |size_fn| {
                var mut_val = val;
                const result = try size_fn(allocator, &mut_val, &[_]*ast.Expr{}, env);
                if (result != .number) {
                    try writer_err.print("len(arr|str|std_instance) cannot return a {s}\n", .{@tagName(result)});
                    return error.MalformedStdInstance;
                }
                return .{
                    .number = result.number,
                };
            } else {
                try writer_err.print("len(arr|str|std_instance) cannot be used on standard library type {s} without size method defined\n", .{try getStdStructName(&val)});
                return error.MalformedStdInstance;
            }
        },
        else => {
            if (args.len != 1) {
                try writer_err.print("len(arr|str|std_instance): expected exactly 1 argument, got {d}\n", .{args.len});
                return error.ArgumentCountMismatch;
            }
            return switch (val) {
                .array => |a| .{
                    .number = @floatFromInt(a.items.len),
                },
                .string => |s| .{
                    .number = @floatFromInt(s.len),
                },
                else => {
                    try writer_err.print("len(arr|str|std_instance): only operates on strings and arrays, got a(n) {s}\n", .{@tagName(val)});
                    return error.TypeMismatch;
                },
            };
        },
    }
}

pub fn ref(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("ref(value): expected exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);

    if (val == .reference) {
        return val;
    }

    const heap_val = try allocator.create(Value);
    heap_val.* = val;

    return .{
        .reference = heap_val,
    };
}

pub fn deref(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("deref(reference): expected exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);

    if (val != .reference) {
        try writer_err.print("deref(reference): expected reference, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    return val.reference.*;
}

pub fn detype(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("detype(typed_val): expected exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);

    if (val != .typed_val) {
        try writer_err.print("detype(typed_val): expected typed value, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    return val.typed_val.value.*;
}

pub fn range(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len == 2) {
        try writer_err.print("range(start, end, step): expected 3 arguments, got {d}\n", .{args.len});
        try writer_err.print("  Consider using 'start..end' syntax\n", .{});
        return error.ArgumentCountMismatch;
    } else if (args.len != 3) {
        try writer_err.print("range(start, end, step): expected 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);
    const c = try eval.evalExpr(args[2], env);

    if (a != .number or b != .number or c != .number) {
        try writer_err.print("range(start, end, step): all arguments must be numbers\n", .{});
        try writer_err.print("  Start = {s}\n", .{@tagName(a)});
        try writer_err.print("  End = {s}\n", .{@tagName(b)});
        try writer_err.print("  Step = {s}\n", .{@tagName(c)});
        return error.TypeMismatch;
    }

    const start = a.number;
    const end = b.number;
    const step = c.number;

    if (step == 0) {
        try writer_err.print("range(start, end, step): step cannot be zero\n", .{});
        return error.InvalidStep;
    }

    const diff = end - start;
    const steps = @floor(diff / step);
    const count: usize = if ((step > 0 and start >= end) or (step < 0 and start <= end)) 0 else @as(usize, @intFromFloat(steps)) + 1;

    var result = std.ArrayList(Value).init(allocator);
    for (0..count) |i| {
        const value = start + step * @as(f64, @floatFromInt(i));
        const rounded = @round(value * 1e10) / 1e10;
        try result.append(
            .{
                .number = rounded,
            },
        );
    }

    return .{
        .array = result,
    };
}

pub fn to_string(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("to_string(value) expects exactly 1 argument, got {d}\n", .{args.len});
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
        try writer_err.print("to_number(value) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .string) {
        try writer_err.print("to_number(value) expects a string argument, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    const parsed = std.fmt.parseFloat(f64, val.string) catch {
        try writer_err.print("to_number(value) failed to parse input: \"{s}\"\n", .{val.string});
        return error.ParseFailure;
    };

    return .{
        .number = parsed,
    };
}

pub fn to_bool(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("to_bool(value) expects exactly 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    return .{
        .boolean = coerceBool(val, env),
    };
}

pub fn coerceBool(val: Value, env: ?*Environment) bool {
    return switch (val) {
        .boolean => val.boolean,
        .number => val.number > 0,
        .string => val.string.len != 0,
        .array => val.array.items.len != 0,
        .reference => coerceBool(val.reference.*, env),
        .typed_val => |tv| coerceBool(tv.value.*, env),
        .std_instance => |_| coerceStdInstance(val, env.?),
        .pair => |p| coerceBool(p.first.*, env) and coerceBool(p.second.*, env),
        .continue_signal => true,
        .nil, .std_struct, .break_signal => false,
        else => true, // objects, references, functions, etc. will be considered 'truthy'
    };
}

fn coerceStdInstance(val: Value, env: *Environment) bool {
    var instance = val.std_instance;
    if (instance._type.std_struct.methods.get("size")) |size_fn| {
        var mut_val = val;
        const result = size_fn(env.allocator, &mut_val, &[_]*ast.Expr{}, env) catch {
            return false;
        };

        if (result == .number) {
            return result.number != 0;
        } else {
            return false;
        }
    } else {
        return false;
    }
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
        \\println(range(0, 5, 1));    // [0, 1, 2, 3, 4, 5]
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
        \\["0", "1", "2", "3", "4", "5"]
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
