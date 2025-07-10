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

fn joinHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectStringArgs(args, env, args.len, "path", "join", "str, str, ...");
    const joined = try std.fs.path.join(env.allocator, parts);
    return .{
        .string = joined,
    };
}

fn basenameHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "basename", "path"))[0];
    return .{
        .string = try env.allocator.dupe(u8, std.fs.path.basename(path)),
    };
}

fn dirnameHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "dirname", "path"))[0];
    return .{
        .string = try env.allocator.dupe(u8, std.fs.path.dirname(path) orelse "."),
    };
}

fn extnameHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "extname", "path"))[0];
    return .{
        .string = try env.allocator.dupe(u8, std.fs.path.extension(path)),
    };
}

fn stemHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "stem", "path"))[0];
    return .{
        .string = try env.allocator.dupe(u8, std.fs.path.stem(path)),
    };
}

fn isAbsoluteHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "is_absolute", "path"))[0];
    return .{
        .boolean = std.fs.path.isAbsolute(path),
    };
}

fn isRelativeHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "is_relative", "path"))[0];
    return .{
        .boolean = !std.fs.path.isAbsolute(path),
    };
}

fn normalizeHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "split", "path"))[0];
    const norm = try std.fs.path.resolve(env.allocator, &[_][]const u8{path});
    return .{
        .string = norm,
    };
}

fn splitHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const path = (try expectStringArgs(args, env, 1, "path", "split", "path"))[0];
    const dir = std.fs.path.dirname(path) orelse "";
    const base = std.fs.path.basename(path);
    var list = std.ArrayList(Value).init(env.allocator);
    try list.append(.{
        .string = try env.allocator.dupe(u8, dir),
    });
    try list.append(.{
        .string = try env.allocator.dupe(u8, base),
    });
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
    driver.setWriters(writer);

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

    const tmp_path_one = try std.fs.path.join(allocator, &[_][]const u8{ "foo", "bar", "baz" });
    defer allocator.free(tmp_path_one);
    const tmp_path_two = try std.fs.path.join(allocator, &[_][]const u8{ "foo", "baz" });
    defer allocator.free(tmp_path_two);
    const expected = try std.fmt.allocPrint(allocator,
        \\{s}
        \\zsh
        \\/usr/bin
        \\.gz
        \\archive.tar
        \\true
        \\true
        \\{s}
        \\["/usr/bin", "zsh"]
        \\
    , .{ tmp_path_one, tmp_path_two });
    defer allocator.free(expected);

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
