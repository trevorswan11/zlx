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
const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);
    try map.put("PI", .{
        .number = std.math.pi,
    });
    try map.put("E", .{
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
    try pack(&map, "log_base", logBaseHandler);

    // Binary functions
    try pack(&map, "pow", powHandler);
    try pack(&map, "min", minHandler);
    try pack(&map, "max", maxHandler);
    try pack(&map, "atan2", atan2Handler);

    return .{
        .object = map,
    };
}

fn sqrtHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const arg = (try expectNumberArgs(args, env, 1, "math", "sqrt", "num"))[0];
    if (arg < 0) {
        return .{
            .string = "NaN",
        };
    }
    return .{
        .number = std.math.sqrt(arg),
    };
}

fn absHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = @abs((try expectNumberArgs(args, env, 1, "math", "abs", "num"))[0]),
    };
}

fn sinHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.sin((try expectNumberArgs(args, env, 1, "math", "sin", "num"))[0]),
    };
}

fn cosHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.cos((try expectNumberArgs(args, env, 1, "math", "cos", "num"))[0]),
    };
}

fn tanHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.tan((try expectNumberArgs(args, env, 1, "math", "tan", "num"))[0]),
    };
}

fn logHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.log(f64, std.math.e, (try expectNumberArgs(args, env, 1, "math", "log", "num"))[0]),
    };
}

fn expHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.exp((try expectNumberArgs(args, env, 1, "math", "exp", "num"))[0]),
    };
}

fn powHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectNumberArgs(args, env, 2, "math", "pow", "num");
    return .{
        .number = std.math.pow(f64, vals[0], vals[1]),
    };
}

fn asinHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.asin((try expectNumberArgs(args, env, 1, "math", "asin", "num"))[0]),
    };
}

fn acosHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.acos((try expectNumberArgs(args, env, 1, "math", "acos", "num"))[0]),
    };
}

fn atanHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.atan((try expectNumberArgs(args, env, 1, "math", "atan", "num"))[0]),
    };
}

fn atan2Handler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectNumberArgs(args, env, 2, "math", "atan2", "num");
    return .{
        .number = std.math.atan2(vals[0], vals[1]),
    };
}

fn log10Handler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.log10((try expectNumberArgs(args, env, 1, "math", "log10", "num"))[0]),
    };
}

fn floorHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.floor((try expectNumberArgs(args, env, 1, "math", "floor", "num"))[0]),
    };
}

fn ceilHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.ceil((try expectNumberArgs(args, env, 1, "math", "ceil", "num"))[0]),
    };
}

fn roundHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return .{
        .number = std.math.round((try expectNumberArgs(args, env, 1, "math", "round", "num"))[0]),
    };
}

fn minHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectNumberArgs(args, env, 2, "math", "min", "num");
    return .{
        .number = @min(vals[0], vals[1]),
    };
}

fn maxHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectNumberArgs(args, env, 2, "math", "max", "num");
    return .{
        .number = @max(vals[0], vals[1]),
    };
}

fn logBaseHandler(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectNumberArgs(args, env, 2, "math", "log_base", "base, num");
    const base = vals[0];
    const num = vals[1];

    return .{
        .number = std.math.log(f64, base, num),
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
