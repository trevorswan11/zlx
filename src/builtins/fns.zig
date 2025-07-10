const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("../interpreter/interpreter.zig");
const driver = @import("../utils/driver.zig");
const builtins = @import("builtins.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

const getStdStructName = builtins.getStdStructName;
const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

pub fn print(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_out = driver.getWriterOut();
    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try toPrintableString(val, env);
        defer env.allocator.free(str);
        try writer_out.print("{s}", .{str});
    }
    return .nil;
}

pub fn println(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_out = driver.getWriterOut();
    if (args.len == 0) {
        try writer_out.print("\n", .{});
    }

    for (args) |arg_expr| {
        const val = try eval.evalExpr(arg_expr, env);
        const str = try toPrintableString(val, env);
        defer env.allocator.free(str);
        try writer_out.print("{s}\n", .{str});
    }
    return .nil;
}

fn toPrintableString(val: Value, env: *Environment) ![]u8 {
    switch (val) {
        .std_instance => |instance| {
            if (instance._type.std_struct.methods.get("str")) |str_fn| {
                var mut_val = val;
                const result = try str_fn(&mut_val, &[_]*ast.Expr{}, env);
                return try result.toString(env.allocator);
            } else {
                return try env.allocator.dupe(u8, "<std_instance: no .str()>");
            }
        },
        .std_struct => |_| {
            return try env.allocator.dupe(u8, "<std_struct>");
        },
        else => {
            return try val.toString(env.allocator);
        },
    }
}

pub fn len(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    var val = (try expectValues(args, env, 1, "function", "len", "size_supported_val"))[0];
    switch (val) {
        .std_instance => |instance| {
            if (instance._type.std_struct.methods.get("size")) |size_fn| {
                var mut_val = val;
                const result = try size_fn(&mut_val, &[_]*ast.Expr{}, env);
                if (result != .number) {
                    try writer_err.print("len(size_supported_val) cannot return a {s}\n", .{@tagName(result)});
                    return error.MalformedStdInstance;
                }
                return .{
                    .number = result.number,
                };
            } else {
                try writer_err.print("len(size_supported_val) cannot be used on standard library type {s} without size method defined\n", .{try getStdStructName(&val)});
                return error.MalformedStdInstance;
            }
        },
        else => {
            if (args.len != 1) {
                try writer_err.print("len(size_supported_val): expected exactly 1 argument, got {d}\n", .{args.len});
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
                    try writer_err.print("len(size_supported_val): only operates on strings and arrays, got a(n) {s}\n", .{@tagName(val)});
                    return error.TypeMismatch;
                },
            };
        },
    }
}

pub fn ref(args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "function", "ref", "value"))[0];
    if (val == .reference) {
        return val;
    }

    const heap_val = try env.allocator.create(Value);
    heap_val.* = val;

    return .{
        .reference = heap_val,
    };
}

pub fn deref(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const val = (try expectValues(args, env, 1, "function", "deref", "reference"))[0];

    if (val != .reference) {
        try writer_err.print("deref(reference): expected reference, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    return val.reference.*;
}

pub fn detype(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const val = (try expectValues(args, env, 1, "function", "detype", "typed_val"))[0];

    if (val != .typed_val) {
        try writer_err.print("detype(typed_val): expected typed value, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    return val.typed_val.value.*;
}

pub fn raw(args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "function", "raw", "value"))[0];
    return val.raw();
}

pub fn range(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    const parts = expectNumberArgs(args, env, 3, "function", "range", "start, end, step") catch |err| {
        if (args.len == 2) {
            try writer_err.print("  Consider using 'start..end' syntax\n", .{});
        }
        return err;
    };

    const start = parts[0];
    const end = parts[1];
    const step = parts[2];

    if (step == 0) {
        try writer_err.print("range(start, end, step): step cannot be zero\n", .{});
        return error.InvalidStep;
    }

    const diff = end - start;
    const steps = @floor(diff / step);
    const count: usize = if ((step > 0 and start >= end) or (step < 0 and start <= end)) 0 else @as(usize, @intFromFloat(steps)) + 1;

    var result = std.ArrayList(Value).init(env.allocator);
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

pub fn to_string(args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "function", "to_string", "value"))[0];
    const str = try toPrintableString(val, env);
    return .{
        .string = str,
    };
}

pub fn to_number(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const str = (try expectStringArgs(args, env, 1, "function", "to_number", "str"))[0];

    const parsed = std.fmt.parseFloat(f64, str) catch {
        try writer_err.print("to_number(value): failed to parse input \"{s}\"\n", .{str});
        return error.ParseFailure;
    };

    return .{
        .number = parsed,
    };
}

pub fn to_bool(args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "function", "to_bool", "value"))[0];
    return .{
        .boolean = coerceBool(val, env),
    };
}

pub fn to_ascii(args: []const *ast.Expr, env: *interpreter.Environment) !Value {
    const writer_err = driver.getWriterErr();
    const str = (try expectStringArgs(args, env, 1, "function", "to_ascii", "ascii_char"))[0];
    if (str.len != 1) {
        try writer_err.print("to_ascii(ascii_char): {s} is not a valid character. Must be length 1\n", .{str});
        return error.TypeMismatch;
    }

    const code = str[0];
    if (!std.ascii.isAscii(code)) {
        try writer_err.print("to_ascii(ascii_char): {c} is not a valid ascii character\n", .{code});
        return error.OutOfRange;
    }

    return .{
        .number = @floatFromInt(code),
    };
}

pub fn from_ascii(args: []const *ast.Expr, env: *interpreter.Environment) !Value {
    const writer_err = driver.getWriterErr();
    const num = (try expectNumberArgs(args, env, 1, "function", "from_ascii", "ascii_num"))[0];

    const code: u8 = @intFromFloat(num);
    if (!std.ascii.isAscii(code)) {
        try writer_err.print("from_ascii(ascii_num): {d} is not a valid ascii code\n", .{code});
        return error.OutOfRange;
    }

    const str = try env.allocator.alloc(u8, 1);
    str[0] = code;
    return .{
        .string = str,
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
        .nil, .std_struct, .break_signal, .return_value => false,
        else => true, // objects, references, functions, etc. will be considered 'truthy'
    };
}

fn coerceStdInstance(val: Value, env: *Environment) bool {
    var instance = val.std_instance;
    if (instance._type.std_struct.methods.get("size")) |size_fn| {
        var mut_val = val;
        const result = size_fn(&mut_val, &[_]*ast.Expr{}, env) catch {
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

pub fn format(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len < 1) {
        try writer_err.print("format(format, ...) expects at least 1 argument\n", .{});
        return error.ArgumentCountMismatch;
    }

    const fmt = (try expectStringArgs(args[0..1], env, 1, "function", "format", "format, ..."))[0];
    const values = try expectValues(args[1..], env, args[1..].len, "function", "format", "format, ...");

    if (values.len == 0) {
        return .{
            .string = try env.allocator.dupe(u8, fmt),
        };
    }

    var output = std.ArrayList(u8).init(env.allocator);
    defer output.deinit();
    const writer = output.writer();

    var i: usize = 0;
    var pos: usize = 0;

    while (pos < fmt.len) {
        if (fmt[pos] == '{' and pos + 1 < fmt.len and fmt[pos + 1] == '}') {
            if (i >= values.len) {
                try writer_err.print("Not enough arguments for format string\n", .{});
                return error.ArgumentCountMismatch;
            }

            try writer.print("{s}", .{try toPrintableString(values[i], env)});
            i += 1;
            pos += 2;
        } else {
            try writer.writeByte(fmt[pos]);
            pos += 1;
        }
    }

    return .{
        .string = try output.toOwnedSlice(),
    };
}

pub fn zip(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len < 1) {
        try writer_err.print("zip(arrays...) expects at least 1 argument\n", .{});
        return error.ArgumentCountMismatch;
    }

    // Collect the arrays and determine the minimum length
    const arrays = try expectArrayArgs(args, env, args.len, "function", "zip", "arrays...");
    var min_length = arrays[0].items.len;
    for (1..arrays.len) |i| {
        if (arrays[i].items.len < min_length) {
            min_length = arrays[i].items.len;
        }
    }

    // Zip the args into a single array
    var result = std.ArrayList(Value).init(env.allocator);
    for (0..min_length) |i| {
        var line = std.ArrayList(Value).init(env.allocator);
        for (0..arrays.len) |j| {
            try line.append(arrays[j].items[i]);
        }
        try result.append(.{
            .array = line,
        });
    }

    return .{
        .array = result,
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
