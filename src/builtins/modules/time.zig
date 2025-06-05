const std = @import("std");

const ast = @import("../../parser/ast.zig");
const environment = @import("../../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
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
