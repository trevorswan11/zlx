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

    try pack(&map, "rand", randHandler);
    try pack(&map, "randint", randintHandler);
    try pack(&map, "choice", choiceHandler);

    return .{
        .object = map,
    };
}

fn randHandler(_: std.mem.Allocator, args: []const *ast.Expr, _: *Environment) !Value {
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const rand_val = prng.random().float(f64);
    return .{
        .number = rand_val,
    };
}

fn randintHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const a = try interpreter.eval.evalExpr(args[0], env);
    const b = try interpreter.eval.evalExpr(args[1], env);
    if (a != .number or b != .number) {
        return error.TypeMismatch;
    }

    const min: i64 = @intFromFloat(a.number);
    const max: i64 = @intFromFloat(b.number);

    if (min >= max) {
        return error.InvalidRange;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const rand_int = prng.random().intRangeAtMost(i64, min, max);
    return .{
        .number = @floatFromInt(rand_int),
    };
}

fn choiceHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }

    const val = try interpreter.eval.evalExpr(args[0], env);
    if (val != .array) {
        return error.TypeMismatch;
    }

    const array = val.array;
    if (array.items.len == 0) {
        return error.OutOfBounds;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const index = prng.random().uintLessThan(usize, array.items.len);

    return array.items[index];
}

// === TESTING ===

const parser = @import("../../parser/parser.zig");
const testing = std.testing;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "random_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    eval.setWriters(writer);

    const source =
        \\import random;
        \\
        \\let r = random.rand();
        \\println(r); // something like 0.73218
        \\
        \\let i = random.randint(1, 10);
        \\println(i); // 1 to 10
        \\
        \\let val = random.choice([1, 2, 3, 4]);
        \\println(val); // any of 1, 2, 3, 4
    ;

    const block = try parser.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    var lines = std.mem.tokenizeScalar(u8, output_buffer.items, '\n');
    var actuals = std.ArrayList(f64).init(allocator);
    defer actuals.deinit();
    while (lines.next()) |line| {
        const actual = try std.fmt.parseFloat(f64, line);
        try actuals.append(actual);
    }

    const actual_slice = try actuals.toOwnedSlice();
    try expect(actual_slice[0] > 0 and actual_slice[0] < 1);
    try expect(actual_slice[1] >= 1 and actual_slice[1] <= 10);
    try expect(actual_slice[2] == 1 or actual_slice[2] == 2 or actual_slice[2] == 3 or actual_slice[2] == 4);
}
