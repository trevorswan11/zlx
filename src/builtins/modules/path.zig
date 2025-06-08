const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
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

    return .{
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
    return .{
        .string = joined,
    };
}

fn basenameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return .{
        .string = try allocator.dupe(u8, std.fs.path.basename(path)),
    };
}

fn dirnameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return .{
        .string = try allocator.dupe(u8, std.fs.path.dirname(path) orelse "."),
    };
}

fn extnameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return .{
        .string = try allocator.dupe(u8, std.fs.path.extension(path)),
    };
}

fn stemHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return .{
        .string = try allocator.dupe(u8, std.fs.path.stem(path)),
    };
}

fn isAbsoluteHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return .{
        .boolean = std.fs.path.isAbsolute(path),
    };
}

fn isRelativeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    return .{
        .boolean = !std.fs.path.isAbsolute(path),
    };
}

fn normalizeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    const norm = try std.fs.path.resolve(allocator, &[_][]const u8{path});
    return .{
        .string = norm,
    };
}

fn splitHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(allocator, args, env, 1))[0];
    const dir = std.fs.path.dirname(path) orelse "";
    const base = std.fs.path.basename(path);
    var list = std.ArrayList(Value).init(allocator);
    try list.append(
        .{
            .string = try allocator.dupe(u8, dir),
        },
    );
    try list.append(
        .{
            .string = try allocator.dupe(u8, base),
        },
    );
    return .{
        .array = list,
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "path_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    eval.setWriters(writer);

    const source =
        \\import path;
        \\
        \\println(path.join("foo", "bar", "baz"));      // Expect: "foo/bar/baz"
        \\println(path.basename("/usr/bin/zsh"));       // Expect: "zsh"
        \\println(path.dirname("/usr/bin/zsh"));        // Expect: "/usr/bin"
        \\println(path.extname("archive.tar.gz"));      // Expect: ".gz"
        \\println(path.stem("archive.tar.gz"));         // Expect: "archive.tar"
        \\println(path.is_absolute("/usr/bin/zsh"));    // Expect: true
        \\println(path.is_relative("foo/bar"));         // Expect: true
        \\println(path.normalize("foo//bar/../baz"));   // Expect: "foo/baz"
        \\
        \\let parts = path.split("/usr/bin/zsh");
        \\println(parts);  // Expect: ["/usr/bin", "zsh"]
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\foo\bar\baz
        \\zsh
        \\/usr/bin
        \\.gz
        \\archive.tar
        \\true
        \\true
        \\foo\baz
        \\["/usr/bin", "zsh"]
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
