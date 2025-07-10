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

    try pack(&map, "rand", randHandler);
    try pack(&map, "randint", randintHandler);
    try pack(&map, "choice", choiceHandler);

    return .{
        .object = map,
    };
}

fn randHandler(args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "random", "rand", "");

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const rand_val = prng.random().float(f64);
    return .{
        .number = rand_val,
    };
}

fn randintHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const parts = try expectNumberArgs(args, env, 2, "random", "rand", "start_inclusive, end_inclusive");

    const min: i64 = @intFromFloat(parts[0]);
    const max: i64 = @intFromFloat(parts[1]);

    if (min >= max) {
        try writer_err.print("random.randint(start_inclusive, end_inclusive) requires min < max, but got min = {d}, max = {d}\n", .{ min, max });
        return error.InvalidRange;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const rand_int = prng.random().intRangeAtMost(i64, min, max);
    return .{
        .number = @floatFromInt(rand_int),
    };
}

fn choiceHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const array = (try expectArrayArgs(args, env, 1, "random", "choice", "array"))[0];

    if (array.items.len == 0) {
        try writer_err.print("random.choice(arr) cannot select from an empty array\n", .{});
        return error.OutOfBounds;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const index = prng.random().uintLessThan(usize, array.items.len);

    return array.items[index];
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "random_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriters(writer);

    for (0..10) |_| {
        var env = Environment.init(allocator, null);
        defer env.deinit();
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

        const block = try testing.parse(allocator, source);
        _ = try eval.evalStmt(block, &env);

        var lines = std.mem.tokenizeScalar(u8, output_buffer.items, '\n');
        var actuals = std.ArrayList(f64).init(allocator);
        defer actuals.deinit();
        while (lines.next()) |line| {
            const actual = try std.fmt.parseFloat(f64, line);
            try actuals.append(actual);
        }

        const actual_slice = actuals.items;
        try testing.expect(actual_slice[0] > 0 and actual_slice[0] < 1);
        try testing.expect(actual_slice[1] >= 1 and actual_slice[1] <= 10);
        try testing.expect(actual_slice[2] == 1 or actual_slice[2] == 2 or actual_slice[2] == 3 or actual_slice[2] == 4);
    }
}
