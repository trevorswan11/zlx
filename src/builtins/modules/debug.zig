const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "assert", assertHandler);
    try pack(&map, "assertEqual", assertEqualHandler);
    try pack(&map, "assertNotEqual", assertNotEqualHandler);

    return .{
        .object = map,
    };
}

fn assertHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer = eval.getWriterErr();
    if (args.len == 0 or args.len > 2) {
        return error.ArgumentCountMismatch;
    }

    const condition_val = try eval.evalExpr(args[0], env);
    if (condition_val != .boolean) {
        return error.TypeMismatch;
    }

    if (!condition_val.boolean) {
        if (args.len == 2) {
            const msg_val = try eval.evalExpr(args[1], env);
            if (msg_val != .string) {
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
    if (args.len != 2) return error.ArgumentCountMismatch;
    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (!a.eql(b)) {
        try writer.print("Assertion failed: values not equal.\n", .{});
        try writer.print("Left: {}\n", .{a});
        try writer.print("Right: {}\n", .{b});
        return error.AssertionFailed;
    }
    return .nil;
}

fn assertNotEqualHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer = eval.getWriterErr();
    if (args.len != 2) return error.ArgumentCountMismatch;
    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (a.eql(b)) {
        try writer.print("Assertion failed: values unexpectedly equal.\n", .{});
        try writer.print("Value: {}\n", .{a});
        return error.AssertionFailed;
    }
    return .nil;
}

// === TESTInG ===

const parser = @import("../../parser/parser.zig");
const testing = std.testing;

const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "debug_builtin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
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

    const block = try parser.parse(allocator, source);
    const result = eval.evalStmt(block, &env);

    try expectError(error.AssertionFailed, result);
    try expectEqualStrings("Assertion failed: bad math\n", output_buffer.items);
}
