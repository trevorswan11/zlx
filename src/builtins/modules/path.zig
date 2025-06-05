const std = @import("std");

const ast = @import("../../parser/ast.zig");
const environment = @import("../../interpreter/environment.zig");
const eval = environment.eval;

const Environment = environment.Environment;
const Value = environment.Value;
const BuiltinModuleHandler = @import("../builtins.zig").BuiltinModuleHandler;
const pack = @import("../builtins.zig").pack;

fn expectStringArgs(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment, count: usize) ![]const []const u8 {
    if (args.len != count) {
        return error.ArgumentCountMismatch;
    }

    var result = std.ArrayList([]const u8).init(allocator);
    defer result.deinit();

    for (args) |arg| {
        const val = try eval.evalExpr(arg, env);
        if (val != .string) {
            return error.TypeMismatch;
        }
        try result.append(val.string);
    }

    return try result.toOwnedSlice();
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "join", joinHandler);
    try pack(&map, "basename", basenameHandler);
    try pack(&map, "dirname", dirnameHandler);
    try pack(&map, "extname", extnameHandler);
    try pack(&map, "stem", stemHandler);
    try pack(&map, "is_absolute", isAbsoluteHandler);
    try pack(&map, "is_relative", isRelativeHandler);
    try pack(&map, "normalize", normalizeHandler);
    try pack(&map, "split", splitHandler);

    return Value{
        .object = map,
    };
}

fn joinHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();
    for (args) |arg| {
        const val = try eval.evalExpr(arg, env);
        if (val != .string) {
            return error.TypeMismatch;
        }
        try parts.append(val.string);
    }
    const joined = try std.fs.path.join(allocator, parts.items);
    return Value{
        .string = joined,
    };
}

fn basenameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return Value{
        .string = try allocator.dupe(u8, std.fs.path.basename(path)),
    };
}

fn dirnameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return Value{
        .string = try allocator.dupe(u8, std.fs.path.dirname(path) orelse "."),
    };
}

fn extnameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return Value{
        .string = try allocator.dupe(u8, std.fs.path.extension(path)),
    };
}

fn stemHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return Value{
        .string = try allocator.dupe(u8, std.fs.path.stem(path)),
    };
}

fn isAbsoluteHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return Value{
        .boolean = std.fs.path.isAbsolute(path),
    };
}

fn isRelativeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return Value{
        .boolean = !std.fs.path.isAbsolute(path),
    };
}

fn normalizeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    const norm = try std.fs.path.resolve(allocator, &[_][]const u8{path});
    return Value{
        .string = norm,
    };
}

fn splitHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    const dir = std.fs.path.dirname(path) orelse "";
    const base = std.fs.path.basename(path);
    var list = std.ArrayList(Value).init(allocator);
    try list.append(Value{ .string = try allocator.dupe(u8, dir) });
    try list.append(Value{ .string = try allocator.dupe(u8, base) });
    return Value{
        .array = list,
    };
}
