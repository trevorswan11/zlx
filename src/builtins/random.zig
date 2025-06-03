const std = @import("std");

const ast = @import("../ast/ast.zig");
const environment = @import("../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("builtins.zig").BuiltinModuleHandler;

fn packHandler(map: *std.StringHashMap(Value), name: []const u8, builtin: BuiltinModuleHandler) !void {
    try map.put(name, Value{
        .builtin = builtin,
    });
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try packHandler(&map, "rand", randHandler);
    try packHandler(&map, "randint", randintHandler);
    try packHandler(&map, "choice", choiceHandler);

    return Value{
        .object = map,
    };
}

fn randHandler(_: std.mem.Allocator, args: []const *ast.Expr, _: *Environment) !Value {
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const rand_val = prng.random().float(f64);
    return Value{
        .number = rand_val,
    };
}

fn randintHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const a = try environment.eval.evalExpr(args[0], env);
    const b = try environment.eval.evalExpr(args[1], env);
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
    return Value{
        .number = @floatFromInt(rand_int),
    };
}

fn choiceHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }

    const val = try environment.eval.evalExpr(args[0], env);
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
