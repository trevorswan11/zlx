const std = @import("std");

const ast = @import("../../parser/ast.zig");
const environment = @import("../../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

fn expectArrayRef(args: []const *ast.Expr, env: *Environment) !*std.ArrayList(Value) {
    if (args.len < 1) {
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .reference or val.reference.* != .array) {
        return error.TypeMismatch;
    }

    return &val.reference.*.array;
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "push", pushHandler);
    try pack(&map, "pop", popHandler);
    try pack(&map, "insert", insertHandler);
    try pack(&map, "remove", removeHandler);
    try pack(&map, "clear", clearHandler);
    try pack(&map, "get", getHandler);
    try pack(&map, "set", setHandler);
    try pack(&map, "slice", sliceHandler);

    return .{
        .object = map,
    };
}

fn pushHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var array = try expectArrayRef(args, env);
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const value = try eval.evalExpr(args[1], env);
    try array.append(value);
    return .nil;
}

fn popHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var array = try expectArrayRef(args, env);
    if (array.items.len == 0) {
        return error.OutOfBounds;
    }

    return array.pop() orelse .nil;
}

fn insertHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var array = try expectArrayRef(args, env);
    if (args.len != 3) {
        return error.ArgumentCountMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    const value = try eval.evalExpr(args[2], env);
    if (index_val != .number) {
        return error.TypeMismatch;
    }

    const index: usize = @intFromFloat(index_val.number);
    if (index > array.items.len) {
        return error.OutOfBounds;
    }

    try array.insert(index, value);
    return .nil;
}

fn removeHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var array = try expectArrayRef(args, env);
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    if (index_val != .number) return error.TypeMismatch;

    const index: usize = @intFromFloat(index_val.number);
    if (index >= array.items.len) {
        return error.OutOfBounds;
    }

    return array.orderedRemove(index);
}

fn clearHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var array = try expectArrayRef(args, env);
    array.clearRetainingCapacity();
    return .nil;
}

fn getHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    if (val != .array) {
        return error.TypeMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    if (index_val != .number) {
        return error.TypeMismatch;
    }

    const index: usize = @intFromFloat(index_val.number);
    if (index >= val.array.items.len) {
        return error.OutOfBounds;
    }

    return val.array.items[index];
}

fn setHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 3) {
        return error.ArgumentCountMismatch;
    }
    const ref_val = try eval.evalExpr(args[0], env);
    if (ref_val != .reference or ref_val.reference.* != .array) {
        return error.TypeMismatch;
    }

    const index_val = try eval.evalExpr(args[1], env);
    if (index_val != .number) {
        return error.TypeMismatch;
    }

    const value = try eval.evalExpr(args[2], env);
    const index: usize = @intFromFloat(index_val.number);

    var array = &ref_val.reference.*.array;
    if (index >= array.items.len) {
        return error.OutOfBounds;
    }

    array.items[index] = value;
    return .nil;
}

fn sliceHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len < 2 or args.len > 3) {
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .array) {
        return error.TypeMismatch;
    }

    const start: usize = @intFromFloat((try eval.evalExpr(args[1], env)).number);
    const end: usize = if (args.len == 3) @intFromFloat((try eval.evalExpr(args[2], env)).number) else val.array.items.len;

    if (start < 0 or end > val.array.items.len or start > end) {
        return error.OutOfBounds;
    }

    var new_array = std.ArrayList(Value).init(allocator);
    for (start..end) |i| {
        try new_array.append(val.array.items[i]);
    }

    return .{
        .array = new_array,
    };
}
