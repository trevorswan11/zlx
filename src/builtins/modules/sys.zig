const std = @import("std");
const builtin = @import("builtin");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;

var process_env: std.process.EnvMap = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);
    process_env = std.process.EnvMap.init(allocator);

    try pack(&map, "args", argsHandler);
    try pack(&map, "getenv", getenvHandler);
    try pack(&map, "setenv", setenvHandler);
    try pack(&map, "unsetenv", unsetenvHandler);
    try pack(&map, "run", runHandler);

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
        try writer_err.print("sys.getenv(key) expects a string argument, got a(n) {s}\n", .{@tagName(key)});
        return error.TypeMismatch;
    }

    const val = process_env.get(key.string) orelse return .nil;
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

    try process_env.put(key.string, val.string);
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
        try writer_err.print("sys.unsetenv(key) expects a string argument, got a(n) {s}\n", .{@tagName(key)});
        return error.TypeMismatch;
    }

    process_env.remove(key.string);
    return .nil;
}

fn runHandler(
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *interpreter.Environment,
) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("sys.run(arr) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const list_val = try eval.evalExpr(args[0], env);
    if (list_val != .array) {
        try writer_err.print("sys.run(arr) expects an array argument, got {s}\n", .{@tagName(list_val)});
        return error.TypeMismatch;
    }

    const argv = list_val.array;
    var arg_list = std.ArrayList([]const u8).init(allocator);

    // Get the users shell and prepend to args
    const shell = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/C" }
    else
        &[_][]const u8{ "sh", "-c" };
    for (shell) |preprocess| {
        try arg_list.append(preprocess);
    }

    // Append the rest of the args
    for (argv.items, 0..) |item, idx| {
        if (item != .string) {
            try writer_err.print("sys.run(arr) expects an array with all string arguments, got {s} @ index {d}\n", .{ @tagName(list_val), idx });
            return error.TypeMismatch;
        }
        try arg_list.append(item.string);
    }

    var stdout_buf = std.ArrayList(u8).init(allocator);
    var stderr_buf = std.ArrayList(u8).init(allocator);

    // Combine the system and local environments to run the command
    var process_env_itr= process_env.iterator();
    const system_env = try std.process.getEnvMap(allocator);
    var system_env_itr = system_env.iterator();

    var tmp_env = std.process.EnvMap.init(allocator);
    while (process_env_itr.next()) |next| {
        try tmp_env.put(next.key_ptr.*, next.value_ptr.*);
    }
    while (system_env_itr.next()) |next| {
        try tmp_env.put(next.key_ptr.*, next.value_ptr.*);
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = arg_list.items,
        .env_map = &tmp_env,
    }) catch |err| {
        try writer_err.print("Failed to run subprocess: {!}\n", .{err});
        return .nil;
    };

    try stdout_buf.appendSlice(result.stdout);
    try stderr_buf.appendSlice(result.stderr);

    var map = std.StringHashMap(Value).init(allocator);
    try map.put("exit_code", .{ .number = @floatFromInt(result.term.Exited) });
    try map.put("stdout", .{ .string = try stdout_buf.toOwnedSlice() });
    try map.put("stderr", .{ .string = try stderr_buf.toOwnedSlice() });

    return Value{ .object = map, };
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
