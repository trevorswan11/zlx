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

var sys_env: std.process.EnvMap = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);
    sys_env = std.process.EnvMap.init(allocator);

    try pack(&map, "args", argsHandler);
    try pack(&map, "getenv", getenvHandler);
    try pack(&map, "setenv", setenvHandler);
    try pack(&map, "unsetenv", unsetenvHandler);

    return .{
        .object = map,
    };
}

fn argsHandler(allocator: std.mem.Allocator, _: []const *ast.Expr, _: *Environment) !Value {
    const args = try std.process.argsAlloc(allocator);
    var array = std.ArrayList(Value).init(allocator);
    for (args) |arg| {
        try array.append(
            .{
                .string = arg,
            },
        );
    }
    return .{
        .array = array,
    };
}

fn getenvHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("sys.getenv(key) expects 1 argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const key = try eval.evalExpr(args[0], env);
    if (key != .string) {
        try writer_err.print("sys.getenv(key) expects a string argument\n", .{});
        try writer_err.print("  Found: {s}\n", .{try key.toString(env.allocator)});
        return error.TypeMismatch;
    }

    const val = sys_env.get(key.string) orelse return .nil;
    return .{
        .string = val,
    };
}

fn setenvHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("sys.setenv(key, value) expects 2 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const key = try eval.evalExpr(args[0], env);
    const val = try eval.evalExpr(args[1], env);

    if (key != .string or val != .string) {
        try writer_err.print("sys.setenv(key, value) expects two string arguments\n", .{});
        try writer_err.print("  Key: {s}\n", .{try key.toString(env.allocator)});
        try writer_err.print("  Value: {s}\n", .{try val.toString(env.allocator)});
        return error.TypeMismatch;
    }

    try sys_env.put(key.string, val.string);
    return .nil;
}

fn unsetenvHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("sys.unsetenv(key) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const key = try eval.evalExpr(args[0], env);
    if (key != .string) {
        try writer_err.print("sys.unsetenv(key) expects a string argument\n", .{});
        try writer_err.print("  Found: {s}\n", .{try key.toString(env.allocator)});
        return error.TypeMismatch;
    }

    sys_env.remove(key.string);
    return .nil;
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "sys_builtin" {
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
        \\import sys;
        \\
        \\let before = sys.getenv("ZLX_TEST_ENV");
        \\println("Before set: " + before);
        \\
        \\sys.setenv("ZLX_TEST_ENV", "active");
        \\let after = sys.getenv("ZLX_TEST_ENV");
        \\println("After set: " + after);
        \\
        \\sys.unsetenv("ZLX_TEST_ENV");
        \\let removed = sys.getenv("ZLX_TEST_ENV");
        \\println("After unset: " + removed);
        \\
        \\let arguments = sys.args();
        \\println("Args:");
        \\foreach i in 0..len(arguments) {
        \\println(arguments[i]);
        \\}
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const output = output_buffer.items;
    const output_str = try std.fmt.allocPrint(allocator, "{s}", .{output});

    try testing.expect(std.mem.containsAtLeast(u8, output_str, 1, "Before set: nil"));
    try testing.expect(std.mem.containsAtLeast(u8, output_str, 1, "After set: active"));
    try testing.expect(std.mem.containsAtLeast(u8, output_str, 1, "After unset: nil"));
    try testing.expect(std.mem.containsAtLeast(u8, output_str, 1, "Args:"));
    try testing.expect(std.mem.containsAtLeast(u8, output_str, 1, "zlx"));
}
