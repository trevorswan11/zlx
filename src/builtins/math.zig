const std = @import("std");

const ast = @import("../ast/ast.zig");
const environment = @import("../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("builtins.zig").BuiltinModuleHandler;

fn packHandler(map: *std.StringHashMap(Value), name: []const u8, builtin: BuiltinModuleHandler) !void {
    try map.put(name, Value{
        .builtin = builtin,
    });
}

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

fn expectTwoNumbers(args: []const *ast.Expr, env: *Environment) !struct { f64, f64 } {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }
    const lhs = try eval.evalExpr(args[0], env);
    const rhs = try eval.evalExpr(args[1], env);
    if (lhs != .number or rhs != .number) {
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
    try packHandler(&map, "sqrt", sqrtHandler);
    try packHandler(&map, "abs", absHandler);
    try packHandler(&map, "sin", sinHandler);
    try packHandler(&map, "cos", cosHandler);
    try packHandler(&map, "tan", tanHandler);
    try packHandler(&map, "asin", asinHandler);
    try packHandler(&map, "acos", acosHandler);
    try packHandler(&map, "atan", atanHandler);
    try packHandler(&map, "log", logHandler);
    try packHandler(&map, "log10", log10Handler);
    try packHandler(&map, "exp", expHandler);
    try packHandler(&map, "floor", floorHandler);
    try packHandler(&map, "ceil", ceilHandler);
    try packHandler(&map, "round", roundHandler);

    // Binary functions
    try packHandler(&map, "pow", powHandler);
    try packHandler(&map, "min", minHandler);
    try packHandler(&map, "max", maxHandler);
    try packHandler(&map, "atan2", atan2Handler);

    return Value{
        .object = map,
    };
}

fn sqrtHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const arg = try expectNumberArg(args, env);
    if (arg < 0) {
        return Value{
            .string = "NaN",
        };
    }
    return Value{
        .number = std.math.sqrt(arg),
    };
}

fn absHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = @abs(try expectNumberArg(args, env)),
    };
}

fn sinHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.sin(try expectNumberArg(args, env)),
    };
}

fn cosHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.cos(try expectNumberArg(args, env)),
    };
}

fn tanHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.tan(try expectNumberArg(args, env)),
    };
}

fn logHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.log(f64, std.math.e, try expectNumberArg(args, env)),
    };
}

fn expHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.exp(try expectNumberArg(args, env)),
    };
}

fn powHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const base = try eval.evalExpr(args[0], env);
    const exponent = try eval.evalExpr(args[1], env);

    if (base != .number or exponent != .number) {
        return error.TypeMismatch;
    }

    return Value{
        .number = std.math.pow(f64, base.number, exponent.number),
    };
}

fn asinHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.asin(try expectNumberArg(args, env)),
    };
}

fn acosHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.acos(try expectNumberArg(args, env)),
    };
}

fn atanHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.atan(try expectNumberArg(args, env)),
    };
}

fn atan2Handler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const vals = try expectTwoNumbers(args, env);
    return Value{
        .number = std.math.atan2(vals[0], vals[1]),
    };
}

fn log10Handler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.log10(try expectNumberArg(args, env)),
    };
}

fn floorHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.floor(try expectNumberArg(args, env)),
    };
}

fn ceilHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.ceil(try expectNumberArg(args, env)),
    };
}

fn roundHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    return Value{
        .number = std.math.round(try expectNumberArg(args, env)),
    };
}

fn minHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const vals = try expectTwoNumbers(args, env);
    return Value{
        .number = @min(vals[0], vals[1]),
    };
}

fn maxHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const vals = try expectTwoNumbers(args, env);
    return Value{
        .number = @max(vals[0], vals[1]),
    };
}
