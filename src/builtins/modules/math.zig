const std = @import("std");

const ast = @import("../../parser/ast.zig");
const environment = @import("../../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

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

    return Value{
        .object = map,
    };
}

fn sqrtHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
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

fn absHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = @abs(try expectNumberArg(args, env)),
    };
}

fn sinHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.sin(try expectNumberArg(args, env)),
    };
}

fn cosHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.cos(try expectNumberArg(args, env)),
    };
}

fn tanHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.tan(try expectNumberArg(args, env)),
    };
}

fn logHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.log(f64, std.math.e, try expectNumberArg(args, env)),
    };
}

fn expHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.exp(try expectNumberArg(args, env)),
    };
}

fn powHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
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

fn asinHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.asin(try expectNumberArg(args, env)),
    };
}

fn acosHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.acos(try expectNumberArg(args, env)),
    };
}

fn atanHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.atan(try expectNumberArg(args, env)),
    };
}

fn atan2Handler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return Value{
        .number = std.math.atan2(vals[0], vals[1]),
    };
}

fn log10Handler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.log10(try expectNumberArg(args, env)),
    };
}

fn floorHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.floor(try expectNumberArg(args, env)),
    };
}

fn ceilHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.ceil(try expectNumberArg(args, env)),
    };
}

fn roundHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    return Value{
        .number = std.math.round(try expectNumberArg(args, env)),
    };
}

fn minHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return Value{
        .number = @min(vals[0], vals[1]),
    };
}

fn maxHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const vals = try expectTwoNumbers(args, env);
    return Value{
        .number = @max(vals[0], vals[1]),
    };
}
