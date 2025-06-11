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

fn expectNumberArg(args: []const *ast.Expr, env: *Environment) !f64 {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("math module: expected 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .number) {
        try writer_err.print("math module: expected a number, got a(n) {s}\n", .{@tagName(val)});
        return error.TypeMismatch;
    }

    return val.number;
}

fn expectTwoNumbers(args: []const *ast.Expr, env: *Environment) !struct { f64, f64 } {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("math module: expected 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const lhs = try eval.evalExpr(args[0], env);
    const rhs = try eval.evalExpr(args[1], env);
    if (lhs != .number or rhs != .number) {
        try writer_err.print("math module: expected both arguments to be numbers\n", .{});
        try writer_err.print("  Left: {s}\n", .{try lhs.toString(env.allocator)});
        try writer_err.print("  Right: {s}\n", .{try rhs.toString(env.allocator)});
        return error.TypeMismatch;
    }

    return .{
        lhs.number,
        rhs.number,
    };
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);
    try map.put("PI", Value{
        .number = std.math.pi,
    });
    try map.put("E", Value{
        .number = std.math.e,
    });

    // Unary functions
    try pack(&map, "sqrt", sqrtHandler);
    try pack(&map, "abs", absHandler);
    try pack(&map, "sin", sinHandler);
    try pack(&map, "cos", cosHandler);
    try pack(&map, "tan", tanHandler);
    try pack(&map, "asin", asinHandler);
    try pack(&map, "acos", acosHandler);
    try pack(&map, "atan", atanHandler);
    try pack(&map, "log", logHandler);
    try pack(&map, "log10", log10Handler);
    try pack(&map, "exp", expHandler);
    try pack(&map, "floor", floorHandler);
    try pack(&map, "ceil", ceilHandler);
    try pack(&map, "round", roundHandler);

    // Binary functions
    try pack(&map, "pow", powHandler);
    try pack(&map, "min", minHandler);
    try pack(&map, "max", maxHandler);
    try pack(&map, "atan2", atan2Handler);

    return .{
        .object = map,
    };
}

fn sqrtHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const arg = try expectNumberArg(args, env);
    if (arg < 0) {
        return .{
            .string = "NaN",
        };
    }
    return .{
        .number = std.math.sqrt(arg),
    };
}

fn absHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = @abs(try expectNumberArg(args, env)),
    };
}

fn sinHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.sin(try expectNumberArg(args, env)),
    };
}

fn cosHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.cos(try expectNumberArg(args, env)),
    };
}

fn tanHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.tan(try expectNumberArg(args, env)),
    };
}

fn logHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.log(f64, std.math.e, try expectNumberArg(args, env)),
    };
}

fn expHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.exp(try expectNumberArg(args, env)),
    };
}

fn powHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return .{
        .number = std.math.pow(f64, vals[0], vals[1]),
    };
}

fn asinHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.asin(try expectNumberArg(args, env)),
    };
}

fn acosHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.acos(try expectNumberArg(args, env)),
    };
}

fn atanHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.atan(try expectNumberArg(args, env)),
    };
}

fn atan2Handler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return .{
        .number = std.math.atan2(vals[0], vals[1]),
    };
}

fn log10Handler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.log10(try expectNumberArg(args, env)),
    };
}

fn floorHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.floor(try expectNumberArg(args, env)),
    };
}

fn ceilHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.ceil(try expectNumberArg(args, env)),
    };
}

fn roundHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.round(try expectNumberArg(args, env)),
    };
}

fn minHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return .{
        .number = @min(vals[0], vals[1]),
    };
}

fn maxHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return .{
        .number = @max(vals[0], vals[1]),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "math_builtin" {
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
        \\import math;
        \\
        \\println(math.PI);
        \\println(math.E);
        \\println(math.abs(-5));
        \\println(math.sqrt(49));
        \\println(math.sin(math.PI / 2));
        \\println(math.cos(math.PI));
        \\println(math.tan(0));
        \\println(math.asin(1));
        \\println(math.acos(1));
        \\println(math.atan(1));
        \\println(math.log(math.E));
        \\println(math.log10(1000));
        \\println(math.exp(1));
        \\println(math.floor(3.7));
        \\println(math.ceil(3.2));
        \\println(math.round(3.6));
        \\println(math.pow(2, 8));
        \\println(math.min(3, 7));
        \\println(math.max(3, 7));
        \\println(math.atan2(1, 1));
        \\println(math.sqrt(-1)); // should produce NaN
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    var lines = std.mem.tokenizeScalar(u8, output_buffer.items, '\n');
    const epsilon = 1e-12;
    const expected: [21]f64 = .{
        std.math.pi,
        std.math.e,
        5.0,
        7.0,
        1.0,
        -1.0,
        0.0,
        std.math.pi / 2.0,
        0.0,
        std.math.pi / 4.0,
        1.0,
        3.0,
        std.math.e,
        3.0,
        4.0,
        4.0,
        256.0,
        3.0,
        7.0,
        std.math.pi / 4.0,
        std.math.nan(f64),
    };

    var i: usize = 0;
    while (lines.next()) |line| : (i += 1) {
        const actual = try std.fmt.parseFloat(f64, line);
        if (std.math.isNan(expected[i])) {
            try testing.expect(std.math.isNan(actual));
        } else {
            try testing.expectApproxEqAbs(expected[i], actual, epsilon);
        }
    }
}
