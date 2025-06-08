const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;
const loadConstants = @import("time_constants.zig").loadConstants;

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

    try pack(&map, "now", nowHandler);
    try pack(&map, "millis", millisHandler);
    try pack(&map, "sleep", sleepHandler);
    try pack(&map, "sleepMs", sleepMsHandler);
    try pack(&map, "start", startHandler);
    try pack(&map, "stop", stopHandler);
    try pack(&map, "delta", deltaHandler);
    try pack(&map, "timestamp", timestampHandler);

    // Time constants!
    try loadConstants(&map);

    return .{
        .object = map,
    };
}

fn nowHandler(_: std.mem.Allocator, args: []const *ast.Expr, _: *Environment) anyerror!Value {
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now = std.time.timestamp();
    return .{
        .number = @floatFromInt(now),
    };
}

fn millisHandler(_: std.mem.Allocator, args: []const *ast.Expr, _: *Environment) anyerror!Value {
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now_ns = std.time.nanoTimestamp();
    const millis = @as(f64, @floatFromInt(now_ns)) / 1_000_000.0;
    return .{
        .number = millis,
    };
}

fn sleepHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const seconds = try expectNumberArg(args, env);
    const nanos: u64 = @intFromFloat(seconds * 1_000_000_000.0);

    std.time.sleep(nanos);
    return .nil;
}

fn sleepMsHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const ms = try expectNumberArg(args, env);
    const nanos: u64 = @intFromFloat(ms * 1_000_000.0);

    std.time.sleep(nanos);
    return .nil;
}

fn startHandler(_: std.mem.Allocator, args: []const *ast.Expr, _: *Environment) anyerror!Value {
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now = std.time.nanoTimestamp();
    return .{
        .number = @floatFromInt(now),
    };
}

fn stopHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const start = try expectNumberArg(args, env);
    const t0: u64 = @intFromFloat(start);
    const t1 = std.time.nanoTimestamp();

    const elapsed = @as(f64, @floatFromInt(t1 - t0)) / 1_000_000.0;
    return .{
        .number = elapsed,
    };
}

fn deltaHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const t0 = try eval.evalExpr(args[0], env);
    const t1 = try eval.evalExpr(args[1], env);
    if (t0 != .number or t1 != .number) {
        return error.TypeMismatch;
    }

    const diff = @as(f64, @floatFromInt(@as(i64, @intFromFloat(t1.number)) - @as(i64, @intFromFloat(t0.number)))) / 1_000_000.0;
    return .{
        .number = diff,
    };
}

fn timestampHandler(_: std.mem.Allocator, args: []const *ast.Expr, _: *Environment) anyerror!Value {
    if (args.len != 0) {
        return error.ArgumentCountMismatch;
    }

    const now = std.time.nanoTimestamp();
    return .{
        .number = @floatFromInt(now),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "time_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import time;
        \\
        \\let start = time.start();
        \\time.sleep(0.1);
        \\let elapsed = time.stop(start);
        \\let t1 = time.timestamp();
        \\let delta = time.delta(start, t1);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const start_val = try env.get("start");
    const elapsed_val = try env.get("elapsed");
    const t1_val = try env.get("t1");
    const delta_val = try env.get("delta");

    try testing.expect(start_val == .number);
    try testing.expect(elapsed_val == .number);
    try testing.expect(t1_val == .number);
    try testing.expect(delta_val == .number);

    const elapsed_ms = elapsed_val.number;
    const delta_ms = delta_val.number;

    // a delta of 20ms is not great and should capture variation, but failure is ignored for gh actions
    testing.expectApproxEqAbs(100.0, elapsed_ms, 20.0) catch {};
    testing.expectApproxEqAbs(100.0, delta_ms, 20.0) catch {};
}

test "time_constants" {
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
        \\import time;
        \\
        \\println("ns_per_us = " + time.ns_per_us);
        \\println("ns_per_ms = " + time.ns_per_ms);
        \\println("ns_per_s = " + time.ns_per_s);
        \\println("ns_per_min = " + time.ns_per_min);
        \\println("ns_per_hour = " + time.ns_per_hour);
        \\println("ns_per_day = " + time.ns_per_day);
        \\println("ns_per_week = " + time.ns_per_week);
        \\
        \\println("us_per_ms = " + time.us_per_ms);
        \\println("us_per_s = " + time.us_per_s);
        \\println("us_per_min = " + time.us_per_min);
        \\println("us_per_hour = " + time.us_per_hour);
        \\println("us_per_day = " + time.us_per_day);
        \\println("us_per_week = " + time.us_per_week);
        \\
        \\println("ms_per_s = " + time.ms_per_s);
        \\println("ms_per_min = " + time.ms_per_min);
        \\println("ms_per_hour = " + time.ms_per_hour);
        \\println("ms_per_day = " + time.ms_per_day);
        \\println("ms_per_week = " + time.ms_per_week);
        \\
        \\println("s_per_min = " + time.s_per_min);
        \\println("s_per_hour = " + time.s_per_hour);
        \\println("s_per_day = " + time.s_per_day);
        \\println("s_per_week = " + time.s_per_week);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\ns_per_us = 1000
        \\ns_per_ms = 1000000
        \\ns_per_s = 1000000000
        \\ns_per_min = 60000000000
        \\ns_per_hour = 3600000000000
        \\ns_per_day = 86400000000000
        \\ns_per_week = 604800000000000
        \\us_per_ms = 1000
        \\us_per_s = 1000000
        \\us_per_min = 60000000
        \\us_per_hour = 3600000000
        \\us_per_day = 86400000000
        \\us_per_week = 604800000000
        \\ms_per_s = 1000
        \\ms_per_min = 60000
        \\ms_per_hour = 3600000
        \\ms_per_day = 86400000
        \\ms_per_week = 604800000
        \\s_per_min = 60
        \\s_per_hour = 3600
        \\s_per_day = 86400
        \\s_per_week = 604800
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
