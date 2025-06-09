const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

fn expectStringArg(args: []const *ast.Expr, env: *Environment) ![]const u8 {
    const writer = eval.getWriterErr();
    if (args.len != 1) {
        try writer.print("debug module: expected 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .string) {
        try writer.print("debug module: expected a string\n", .{});
        try writer.print("  Found: {s}\n", .{try val.toString(env.allocator)});
        return error.TypeMismatch;
    }

    return val.string;
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "assert", assertHandler);
    try pack(&map, "assertEqual", assertEqualHandler);
    try pack(&map, "assertNotEqual", assertNotEqualHandler);
    try pack(&map, "fail", failHandler);

    return .{
        .object = map,
    };
}

fn assertHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer = eval.getWriterErr();
    if (args.len == 0 or args.len > 2) {
        try writer.print("debug.assert(...) expects 1 or 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const condition_val = try eval.evalExpr(args[0], env);
    if (condition_val != .boolean) {
        try writer.print("debug.assert(...) expects a boolean condition as the first argument\n", .{});
        try writer.print("  Found: {s}\n", .{try condition_val.toString(env.allocator)});
        return error.TypeMismatch;
    }

    if (!condition_val.boolean) {
        if (args.len == 2) {
            const msg_val = try eval.evalExpr(args[1], env);
            if (msg_val != .string) {
                try writer.print("debug.assert(...) expects a string as the second argument\n", .{});
                try writer.print("  Found: {s}\n", .{try msg_val.toString(env.allocator)});
                return error.TypeMismatch;
            }
            try writer.print("Assertion failed: {s}\n", .{msg_val.string});
        } else {
            try writer.print("Assertion failed.\n", .{});
        }
        return error.AssertionFailed;
    }

    return .nil;
}

fn assertEqualHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer = eval.getWriterErr();
    if (args.len != 2) {
        try writer.print("debug.assertEqual(...) expects exactly 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (!a.eql(b)) {
        try writer.print("Assertion failed: values not equal.\n", .{});
        try writer.print("  Left: {}\n", .{a});
        try writer.print("  Right: {}\n", .{b});
        return error.AssertionFailed;
    }

    return .nil;
}

fn assertNotEqualHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer = eval.getWriterErr();
    if (args.len != 2) {
        try writer.print("debug.assertNotEqual(...) expects exactly 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (a.eql(b)) {
        try writer.print("Assertion failed: values unexpectedly equal.\n", .{});
        try writer.print("  Value: {}\n", .{a});
        return error.AssertionFailed;
    }

    return .nil;
}

fn failHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer = eval.getWriterErr();
    if (args.len != 0 or args.len != 1) {
        try writer.print("debug.fail(...) expects either 1 or 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    if (args.len == 1) {
        const message = try expectStringArg(args, env);
        try writer.print("{s}\n", .{message});
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
    eval.setWriters(writer);

    const source =
        \\import debug;
        \\
        \\debug.assert(true);
        \\debug.assertEqual(1 + 1, 2);
        \\debug.assert(1 < 2);
        \\debug.assertNotEqual(2 * 2, 5);
        \\debug.assert(1 > 2, "bad math");
    ;

    const block = try testing.parse(allocator, source);
    const result = eval.evalStmt(block, &env);

    try testing.expectError(error.AssertionFailed, result);
    try testing.expectEqualStrings("Assertion failed: bad math\n", output_buffer.items);
}
