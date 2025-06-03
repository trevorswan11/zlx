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

fn expectNumberArg(args: []const *ast.Expr, env: *Environment) !f64 {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .number) {
        return error.TypeMismatch;
    }

    return val.number;
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try packHandler(&map, "now", nowHandler);
    try packHandler(&map, "millis", millisHandler);
    try packHandler(&map, "sleep", sleepHandler);
    try packHandler(&map, "sleepMs", sleepMsHandler);
    try packHandler(&map, "start", startHandler);
    try packHandler(&map, "stop", stopHandler);
    try packHandler(&map, "delta", deltaHandler);
    try packHandler(&map, "timestamp", timestampHandler);

    // Time constants!
    try loadConstants(&map);

    return Value{
        .object = map,
    };
}

fn nowHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    _ = env;
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now = std.time.timestamp();
    return Value{
        .number = @floatFromInt(now),
    };
}

fn millisHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    _ = env;
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now_ns = std.time.nanoTimestamp();
    const millis = @as(f64, @floatFromInt(now_ns)) / 1_000_000.0;
    return Value{
        .number = millis,
    };
}

fn sleepHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;

    const seconds = try expectNumberArg(args, env);
    const nanos: u64 = @intFromFloat(seconds * 1_000_000_000.0);

    std.time.sleep(nanos);

    return Value{ .nil = {} };
}

fn sleepMsHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;

    const ms = try expectNumberArg(args, env);
    const nanos: u64 = @intFromFloat(ms * 1_000_000.0);

    std.time.sleep(nanos);
    return Value{ .nil = {} };
}

fn startHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    _ = env;
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now = std.time.nanoTimestamp();
    return Value{
        .number = @floatFromInt(now),
    };
}

fn stopHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;

    const start = try expectNumberArg(args, env);
    const t0: u64 = @intFromFloat(start);
    const t1 = std.time.nanoTimestamp();

    const elapsed = @as(f64, @floatFromInt(t1 - t0)) / 1_000_000.0;
    return Value{
        .number = elapsed,
    };
}

fn deltaHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    if (args.len != 2) return error.ArgumentCountMismatch;

    const t0 = try eval.evalExpr(args[0], env);
    const t1 = try eval.evalExpr(args[1], env);
    if (t0 != .number or t1 != .number) return error.TypeMismatch;

    const diff = @as(f64, @floatFromInt(@as(i64, @intFromFloat(t1.number)) - @as(i64, @intFromFloat(t0.number)))) / 1_000_000.0;
    return Value{ .number = diff };
}

fn timestampHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    _ = env;

    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now = std.time.nanoTimestamp();
    return Value{
        .number = @floatFromInt(now),
    };
}

fn loadConstants(map: *std.StringHashMap(Value)) !void {
    try map.put("ns_per_us", Value{
        .number = @floatFromInt(std.time.ns_per_us),
    });
    try map.put("ns_per_ms", Value{
        .number = @floatFromInt(std.time.ns_per_ms),
    });
    try map.put("ns_per_s", Value{
        .number = @floatFromInt(std.time.ns_per_s),
    });
    try map.put("ns_per_min", Value{
        .number = @floatFromInt(std.time.ns_per_min),
    });
    try map.put("ns_per_hour", Value{
        .number = @floatFromInt(std.time.ns_per_hour),
    });
    try map.put("ns_per_day", Value{
        .number = @floatFromInt(std.time.ns_per_day),
    });
    try map.put("ns_per_week", Value{
        .number = @floatFromInt(std.time.ns_per_week),
    });

    try map.put("us_per_ms", Value{
        .number = @floatFromInt(std.time.us_per_ms),
    });
    try map.put("us_per_s", Value{
        .number = @floatFromInt(std.time.us_per_s),
    });
    try map.put("us_per_min", Value{
        .number = @floatFromInt(std.time.us_per_min),
    });
    try map.put("us_per_hour", Value{
        .number = @floatFromInt(std.time.us_per_hour),
    });
    try map.put("us_per_day", Value{
        .number = @floatFromInt(std.time.us_per_day),
    });
    try map.put("us_per_week", Value{
        .number = @floatFromInt(std.time.us_per_week),
    });

    try map.put("ms_per_s", Value{
        .number = @floatFromInt(std.time.ms_per_s),
    });
    try map.put("ms_per_min", Value{
        .number = @floatFromInt(std.time.ms_per_min),
    });
    try map.put("ms_per_hour", Value{
        .number = @floatFromInt(std.time.ms_per_hour),
    });
    try map.put("ms_per_day", Value{
        .number = @floatFromInt(std.time.ms_per_day),
    });
    try map.put("ms_per_week", Value{
        .number = @floatFromInt(std.time.ms_per_week),
    });

    try map.put("s_per_min", Value{
        .number = @floatFromInt(std.time.s_per_min),
    });
    try map.put("s_per_hour", Value{
        .number = @floatFromInt(std.time.s_per_hour),
    });
    try map.put("s_per_day", Value{
        .number = @floatFromInt(std.time.s_per_day),
    });
    try map.put("s_per_week", Value{
        .number = @floatFromInt(std.time.s_per_week),
    });
}
