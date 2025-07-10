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

    try pack(&map, "assert", assertHandler);
    try pack(&map, "assert_equal", assertEqualHandler);
    try pack(&map, "assert_not_equal", assertNotEqualHandler);
    try pack(&map, "fail", failHandler);

    return .{
        .object = map,
    };
}

fn assertHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 0 or args.len > 2) {
        try writer_err.print("debug.assert(condition, optional_message) expects 1 or 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const condition_val = try eval.evalExpr(args[0], env);
    if (condition_val != .boolean) {
        try writer_err.print("debug.assert(condition, optional_message) expects a boolean condition as the first argument, got a(n) {s}\n", .{@tagName(condition_val)});
        return error.TypeMismatch;
    }

    if (!condition_val.boolean) {
        if (args.len == 2) {
            const msg = (try expectStringArgs(args[1..], env, 1, "debug", "assert", "condition, message"))[0];
            try writer_err.print("Assertion failed: {s}\n", .{msg});
        } else {
            try writer_err.print("Assertion failed.\n", .{});
        }
        return error.AssertionFailed;
    }

    return .nil;
}

fn assertEqualHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 0 or args.len > 3) {
        try writer_err.print("debug.assertEqual(value_1, value_2, optional_message) expects 2 or 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val_parts = try expectValues(args[0..2], env, 2, "debug", "assert_equal", "value_1, value_2, optional_message");
    const a = val_parts[0];
    const b = val_parts[1];

    if (!a.eql(b)) {
        if (args.len == 3) {
            const msg = (try expectStringArgs(args[2..], env, 1, "debug", "assert_equal", "value_1, value_2, message"))[0];
            try writer_err.print("Assertion failed: {s}\n", .{msg});
            try writer_err.print("  Left: {s}\n", .{try a.toString(env.allocator)});
            try writer_err.print("  Right: {s}\n", .{try b.toString(env.allocator)});
        } else {
            try writer_err.print("Assertion failed.\n", .{});
            try writer_err.print("  Left: {s}\n", .{try a.toString(env.allocator)});
            try writer_err.print("  Right: {s}\n", .{try b.toString(env.allocator)});
        }
        return error.AssertionFailed;
    }

    return .nil;
}

fn assertNotEqualHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 0 or args.len > 3) {
        try writer_err.print("debug.assertNotEqual(value_1, value_2, optional_message) expects 2 or 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (a.eql(b)) {
        if (args.len == 3) {
            const msg = (try expectStringArgs(args[2..], env, 1, "debug", "assert_not_equal", "value_1, value_2, message"))[0];
            try writer_err.print("Assertion failed: {s}\n", .{msg});
            try writer_err.print("  Left: {s}\n", .{try a.toString(env.allocator)});
            try writer_err.print("  Right: {s}\n", .{try b.toString(env.allocator)});
        } else {
            try writer_err.print("Assertion failed.\n", .{});
            try writer_err.print("  Left: {s}\n", .{try a.toString(env.allocator)});
            try writer_err.print("  Right: {s}\n", .{try b.toString(env.allocator)});
        }
        return error.AssertionFailed;
    }

    return .nil;
}

fn failHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0 or args.len != 1) {
        try writer_err.print("debug.fail(optional_message) expects either 0 or 1 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    if (args.len == 1) {
        const message = (try expectStringArgs(args, env, 1, "debug", "fail", "message"))[0];
        try writer_err.print("{s}\n", .{message});
    }
    return error.Fail;
}

// === TESTING ====

const testing = @import("../../testing/testing.zig");

test "debug_builtin" {
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
        \\import debug;
        \\
        \\debug.assert(true);
        \\debug.assert_equal(1 + 1, 2);
        \\debug.assert(1 < 2);
        \\debug.assert_not_equal(2 * 2, 5);
        \\debug.assert(1 > 2, "bad math");
    ;

    const block = try testing.parse(allocator, source);
    const result = eval.evalStmt(block, &env);

    try testing.expectError(error.AssertionFailed, result);
    try testing.expectEqualStrings("Assertion failed: bad math\n", output_buffer.items);
}
