const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const eval = @import("../../interpreter/eval.zig");
const driver = @import("../../utils/driver.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn expectValues(
    args: []const *ast.Expr,
    env: *Environment,
    count: usize,
    module_name: []const u8,
    func_name: []const u8,
) ![]const Value {
    const writer_err = driver.getWriterErr();

    if (args.len != count) {
        if (count == 0) {
            try writer_err.print("{s} module: {s} takes no arguments, got {d}\n", .{ module_name, func_name, args.len });
        } else {
            try writer_err.print("{s} module: {s} expected {d} argument(s), got {d}\n", .{ module_name, func_name, count, args.len });
        }
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList(Value).init(env.allocator);
    defer result.deinit();

    for (args) |arg| {
        const val = try eval.evalExpr(arg, env);
        try result.append(val);
    }

    return try result.toOwnedSlice();
}

pub fn expectStringArgs(
    args: []const *ast.Expr,
    env: *Environment,
    count: usize,
    module_name: []const u8,
    func_name: []const u8,
) ![]const []const u8 {
    const writer_err = driver.getWriterErr();

    if (args.len != count) {
        try writer_err.print("{s} module: {s} expected {d} argument(s), got {d}\n", .{ module_name, func_name, count, args.len });
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList([]const u8).init(env.allocator);
    defer result.deinit();

    for (args, 0..) |arg, idx| {
        const val = try eval.evalExpr(arg, env);
        if (val != .string) {
            try writer_err.print("{s} module: {s} expected a string, got a(n) {s} @ arg {d}\n", .{ module_name, func_name, @tagName(val), idx });
            return error.TypeMismatch;
        }
        try result.append(val.string);
    }

    return try result.toOwnedSlice();
}

pub fn expectArrayArgs(
    args: []const *ast.Expr,
    env: *Environment,
    count: usize,
    module_name: []const u8,
    func_name: []const u8,
) ![]const std.ArrayList(Value) {
    const writer_err = driver.getWriterErr();

    if (args.len != count) {
        try writer_err.print("{s} module: {s} expected {d} argument(s), got {d}\n", .{ module_name, func_name, count, args.len });
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList(std.ArrayList(Value)).init(env.allocator);
    defer result.deinit();

    for (args, 0..) |arg, idx| {
        const val = try eval.evalExpr(arg, env);
        if (val != .array) {
            try writer_err.print("{s} module: {s} expected an array, got a(n) {s} @ arg {d}\n", .{ module_name, func_name, @tagName(val), idx });
            return error.TypeMismatch;
        }
        try result.append(val.array);
    }

    return try result.toOwnedSlice();
}

pub fn expectNumberArgs(
    args: []const *ast.Expr,
    env: *Environment,
    count: usize,
    module_name: []const u8,
    func_name: []const u8,
) ![]const f64 {
    const writer_err = driver.getWriterErr();

    if (args.len != count) {
        try writer_err.print("{s} module: {s} expected {d} argument(s), got {d}\n", .{ module_name, func_name, count, args.len });
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList(f64).init(env.allocator);
    defer result.deinit();

    for (args, 0..) |arg, idx| {
        const val = try eval.evalExpr(arg, env);
        if (val != .number) {
            try writer_err.print("{s} module: {s} expected an array, got a(n) {s} @ arg {d}\n", .{ module_name, func_name, @tagName(val), idx });
            return error.TypeMismatch;
        }
        try result.append(val.number);
    }

    return try result.toOwnedSlice();
}

pub fn expectNumberArrays(
    allocator: std.mem.Allocator,
    arrays: []const std.ArrayList(Value),
    module_name: []const u8,
    func_name: []const u8,
) ![]const []const f64 {
    const writer_err = driver.getWriterErr();
    var result = std.ArrayList([]const f64).init(allocator);
    defer result.deinit();

    for (arrays) |arr| {
        var nums = try std.ArrayList(f64).initCapacity(allocator, arr.items.len);
        defer nums.deinit();
        for (arr.items, 0..) |val, idx| {
            if (val != .number) {
                try writer_err.print("{s} module: {s} expected array packed with numbers but found type {s} @ index {d}\n", .{ module_name, func_name, @tagName(val), idx });
                return error.TypeMismatch;
            }
            try nums.append(val.number);
        }
        try result.append(try nums.toOwnedSlice());
    }

    return try result.toOwnedSlice();
}

pub fn expectArrayRef(args: []const *ast.Expr, env: *Environment) !*std.ArrayList(Value) {
    const writer_err = driver.getWriterErr();
    if (args.len < 1) {
        try writer_err.print("array module: expected at least one argument, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .reference or val.reference.* != .array) {
        try writer_err.print("array module: expression evaluation returned a value that is not a reference to an array\n", .{});
        if (val == .reference) {
            try writer_err.print("  Found a reference to a(n) {s}\n", .{@tagName(val)});
        } else {
            try writer_err.print("  Found a(n) {s}\n", .{@tagName(val.deref())});
        }
        return error.TypeMismatch;
    }

    return &val.reference.*.array;
}
