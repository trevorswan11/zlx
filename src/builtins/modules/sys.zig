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
const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

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
    _ = try expectValues(args, env, 0, "sys", "args", "");

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
    const key = (try expectStringArgs(args, env, 1, "sys", "getenv", "key"))[0];
    const val = process_env.get(key) orelse return .nil;
    return .{
        .string = val,
    };
}

fn setenvHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectStringArgs(args, env, 2, "sys", "setenv", "key, val");
    const key = parts[0];
    const val = parts[1];

    try process_env.put(key, val);
    return .nil;
}

fn unsetenvHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const key = (try expectStringArgs(args, env, 1, "sys", "getenv", "key"))[0];
    process_env.remove(key);
    return .nil;
}

fn runHandler(
    args: []const *ast.Expr,
    env: *interpreter.Environment,
) !Value {
    const writer_err = driver.getWriterErr();
    const command = (try expectStringArgs(args, env, 1, "sys", "run", "cmd"))[0];

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
        try writer_err.print("sys.run(cmd): failed to run subprocess: {!}\n", .{err});
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
    const prompt_val = (try expectStringArgs(args, env, 1, "sys", "input", "prompt"))[0];
    try writer_out.print("{s}", .{prompt_val});

    const stdin = std.io.getStdIn().reader();
    const input_line = try stdin.readUntilDelimiterOrEofAlloc(env.allocator, '\n', 1024);

    if (input_line) |il| {
        const trimmed = std.mem.trimRight(u8, il, "\r\n");
        return .{
            .string = trimmed,
        };
    } else {
        return .nil;
    }
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
