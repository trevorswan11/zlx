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
    try pack(&map, "input", inputHandler);

    return .{
        .object = map,
    };
}

fn argsHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("sys.args() expects 0 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const sys_args = try std.process.argsAlloc(env.allocator);
    var array = std.ArrayList(Value).init(env.allocator);
    for (sys_args) |arg| {
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

fn getenvHandler(args: []const *ast.Expr, env: *Environment) !Value {
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

fn setenvHandler(args: []const *ast.Expr, env: *Environment) !Value {
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

fn unsetenvHandler(args: []const *ast.Expr, env: *Environment) !Value {
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
    args: []const *ast.Expr,
    env: *interpreter.Environment,
) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("sys.run(cmd) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const cmd_val = try eval.evalExpr(args[0], env);
    if (cmd_val != .string) {
        try writer_err.print("sys.run(cmd) expects a string argument, got {s}\n", .{@tagName(cmd_val)});
        return error.TypeMismatch;
    }

    const command = cmd_val.string;
    var arg_list = std.ArrayList([]const u8).init(env.allocator);

    // Prepend shell command
    const shell = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/C" }
    else
        &[_][]const u8{ "sh", "-c" };
    try arg_list.appendSlice(shell);

    // Append the command string
    try arg_list.append(command);

    // Buffers for output
    var stdout_buf = std.ArrayList(u8).init(env.allocator);
    var stderr_buf = std.ArrayList(u8).init(env.allocator);

    // Merge environment maps
    var tmp_env = std.process.EnvMap.init(env.allocator);
    const system_env = try std.process.getEnvMap(env.allocator);
    var system_env_itr = system_env.iterator();
    var process_env_itr = process_env.iterator();

    while (process_env_itr.next()) |entry| {
        try tmp_env.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    while (system_env_itr.next()) |entry| {
        try tmp_env.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Run the command
    const result = std.process.Child.run(.{
        .allocator = env.allocator,
        .argv = arg_list.items,
        .env_map = &tmp_env,
    }) catch |err| {
        try writer_err.print("Failed to run subprocess: {!}\n", .{err});
        return .nil;
    };

    try stdout_buf.appendSlice(result.stdout);
    try stderr_buf.appendSlice(result.stderr);

    var map = std.StringHashMap(Value).init(env.allocator);
    try map.put("exit_code", .{ .number = @floatFromInt(result.term.Exited) });
    try map.put("stdout", .{ .string = try stdout_buf.toOwnedSlice() });
    try map.put("stderr", .{ .string = try stderr_buf.toOwnedSlice() });

    return .{
        .object = map,
    };
}

fn inputHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_out = driver.getWriterOut();
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("sys.input(prompt) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const prompt_val = try eval.evalExpr(args[0], env);
    if (prompt_val != .string) {
        try writer_err.print("sys.input(prompt) expects a string argument\n", .{});
        try writer_err.print("  Got: {s}\n", .{try prompt_val.toString(env.allocator)});
        return error.TypeMismatch;
    }

    try writer_out.print("{s}", .{prompt_val.string});

    var line_buf = std.ArrayList(u8).init(env.allocator);
    defer line_buf.deinit();

    const stdin = std.io.getStdIn().reader();

    const input_line = try stdin.readUntilDelimiterOrEofAlloc(env.allocator, '\n', 1024);
    if (input_line == null) return .nil;
    return .{
        .string = input_line.?,
    };
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
}
