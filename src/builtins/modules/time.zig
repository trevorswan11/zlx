const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const time_constants = @import("time_constants.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;
const expectNumberArgs = builtins.expectNumberArgs;
const loadConstants = time_constants.loadConstants;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "now", nowHandler);
    try pack(&map, "millis", millisHandler);
    try pack(&map, "sleep", sleepHandler);
    try pack(&map, "sleep_ms", sleepMsHandler);
    try pack(&map, "timestamp", timestampHandler);

    // Time constants!
    try loadConstants(&map);

    return .{
        .object = map,
    };
}

fn nowHandler(args: []const *ast.Expr, _: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("time.now() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const now = std.time.timestamp();
    return .{
        .number = @floatFromInt(now),
    };
}

fn millisHandler(args: []const *ast.Expr, _: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("time.millis() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const now_ns = std.time.nanoTimestamp();
    const millis = @as(f64, @floatFromInt(now_ns)) / 1_000_000.0;
    return .{
        .number = millis,
    };
}

fn sleepHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const seconds = (try expectNumberArgs(args, env, 1, "time", "sleep"))[0];
    const nanos: u64 = @intFromFloat(seconds * 1_000_000_000.0);

    std.time.sleep(nanos);
    return .nil;
}

fn sleepMsHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const ms = (try expectNumberArgs(args, env, 1, "time", "sleep_ms"))[0];
    const nanos: u64 = @intFromFloat(ms * 1_000_000.0);

    std.time.sleep(nanos);
    return .nil;
}

fn timestampHandler(args: []const *ast.Expr, _: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("time.timestamp() expects 0 arguments but got {d}\n", .{args.len});
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
        \\let start = time.millis();
        \\time.sleep(0.1);
        \\let end = time.millis();
        \\let t1 = time.timestamp();
        \\let delta = end - start;
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const start_val = try env.get("start");
    const end_val = try env.get("end");
    const t1_val = try env.get("t1");
    const delta_val = try env.get("delta");

    try testing.expect(start_val == .number);
    try testing.expect(end_val == .number);
    try testing.expect(t1_val == .number);
    try testing.expect(delta_val == .number);

    // a delta of 20ms is not great and should capture variation, but failure is ignored for gh actions
    const delta_ms = delta_val.number;
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
    driver.setWriters(writer);

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
