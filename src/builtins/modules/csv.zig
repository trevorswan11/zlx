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

fn expectStringArgs(
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
    count: usize,
) ![]const []const u8 {
    const writer_err = driver.getWriterErr();

    if (args.len != count) {
        try writer_err.print("csv module: expected {d} argument(s), got {d}\n", .{ count, args.len });
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList([]const u8).init(allocator);
    defer result.deinit();

    for (args, 0..) |arg, idx| {
        const val = try eval.evalExpr(arg, env);
        if (val != .string) {
            try writer_err.print("csv module: expected a string, got a {s} @ arg {d}\n", .{@tagName(val), idx});
            return error.TypeMismatch;
        }
        try result.append(val.string);
    }

    return try result.toOwnedSlice();
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "read", readHandler);
    try pack(&map, "read", writeHandler);
    try pack(&map, "read", parseHandler);
    try pack(&map, "read", stringifyHandler);

    return .{
        .object = map,
    };
}

fn readHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const func_args = try expectStringArgs(allocator, args, env, 1);
    const filepath = func_args[0];
    const contents = try std.fs.cwd().readFileAlloc(allocator, filepath, 1 << 20);
    defer allocator.free(contents);

    return try parseCSV(allocator, contents);
}

fn writeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const func_args = try expectStringArgs(allocator, args, env, 2);
    const filepath = try func_args[0];
    const contents = stringifyCSV(allocator, func_args[1]);
    try std.fs.cwd().openFile(sub_path: []const u8, flags: OpenFlags)

}

fn parseHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
}

fn stringifyHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "csv_builtin" {}
