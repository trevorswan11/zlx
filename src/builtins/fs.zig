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

fn expectStringArg(args: []const *ast.Expr, env: *Environment) ![]const u8 {
    if (args.len != 1) {
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    if (val != .string) {
        return error.TypeMismatch;
    }

    return val.string;
}

fn expectTwoStrings(args: []const *ast.Expr, env: *Environment) !struct { []const u8, []const u8 } {
    if (args.len != 2) {
        return error.ArgumentCountMismatch;
    }

    const a = try eval.evalExpr(args[0], env);
    const b = try eval.evalExpr(args[1], env);

    if (a != .string or b != .string) {
        return error.TypeMismatch;
    }

    return .{ a.string, b.string };
}

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try packHandler(&map, "read", readHandler);
    try packHandler(&map, "write", writeHandler);
    try packHandler(&map, "exists", existsHandler);
    try packHandler(&map, "delete", deleteHandler);
    try packHandler(&map, "list", listHandler);
    try packHandler(&map, "mkdir", mkdirHandler);
    try packHandler(&map, "rmdir", rmdirHandler);
    try packHandler(&map, "rm", rmHandler);
    try packHandler(&map, "copy", copyHandler);
    try packHandler(&map, "rename", renameHandler);
    try packHandler(&map, "is_dir", isDirHandler);
    try packHandler(&map, "read_lines", readLinesHandler);
    try packHandler(&map, "touch", touchHandler);
    try packHandler(&map, "append", appendHandler);

    return Value{
        .object = map,
    };
}

fn readHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = try expectStringArg(args, env);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    return Value{
        .string = contents,
    };
}

fn writeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const parts = try expectTwoStrings(args, env);
    const file = try std.fs.cwd().createFile(parts[0], .{});
    defer file.close();

    try file.writeAll(parts[1]);
    return .nil;
}

fn existsHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;

    const path = try expectStringArg(args, env);
    std.fs.cwd().access(path, .{}) catch {
        return Value{
            .boolean = false,
        };
    };

    return Value{
        .boolean = true,
    };
}

fn deleteHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;

    const path = try expectStringArg(args, env);
    try std.fs.cwd().deleteFile(path);

    return .nil;
}

fn listHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = try expectStringArg(args, env);
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    var array = std.ArrayList(Value).init(allocator);

    while (try it.next()) |entry| {
        var name = entry.name;

        // Try opening the entry as a subdirectory to check if it's a directory
        const is_dir = blk: {
            var sub = dir.openDir(name, .{}) catch break :blk false;
            sub.close();
            break :blk true;
        };

        if (is_dir) {
            name = try std.fmt.allocPrint(allocator, "{s}/", .{name});
        } else {
            name = try allocator.dupe(u8, name);
        }

        try array.append(Value{
            .string = name,
        });
    }

    return Value{
        .array = array,
    };
}

fn mkdirHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const path = try expectStringArg(args, env);
    try std.fs.cwd().makeDir(path);
    return .nil;
}

fn rmdirHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const path = try expectStringArg(args, env);
    try std.fs.cwd().deleteDir(path);
    return .nil;
}

fn rmHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const path = try expectStringArg(args, env);
    try std.fs.cwd().deleteTree(path);
    return .nil;
}

fn copyHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const parts = try expectTwoStrings(args, env);
    const src_path = parts[0];
    const dst_path = parts[1];

    const cwd = std.fs.cwd();

    // Resolve path info for Dir.openFile
    const src_dir_path = std.fs.path.dirname(src_path) orelse ".";
    const dst_dir_path = std.fs.path.dirname(dst_path) orelse ".";

    const src_basename = std.fs.path.basename(src_path);
    const dst_basename = std.fs.path.basename(dst_path);

    var src_dir = try cwd.openDir(src_dir_path, .{});
    defer src_dir.close();

    src_dir.access(src_basename, .{}) catch {
        return Value{ .string = "Source file not found!" };
    };

    cwd.makePath(dst_dir_path) catch {
        return Value{ .string = "Failed to create destination directory!" };
    };

    var dst_dir = try cwd.openDir(dst_dir_path, .{});
    defer dst_dir.close();

    try src_dir.copyFile(src_basename, dst_dir, dst_basename, .{});

    return .nil;
}

fn renameHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const parts = try expectTwoStrings(args, env);
    try std.fs.cwd().rename(parts[0], parts[1]);
    return .nil;
}

fn isDirHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const path = try expectStringArg(args, env);
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return Value{
            .boolean = false,
        };
    };
    dir.close();
    return Value{
        .boolean = true,
    };
}

fn readLinesHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = try expectStringArg(args, env);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader = std.io.bufferedReader(file.reader());
    var buf = reader.reader();
    var lines = std.ArrayList(Value).init(allocator);

    while (try buf.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096)) |line| {
        try lines.append(Value{ .string = line });
    }

    return Value{ .array = lines };
}

fn touchHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const path = try expectStringArg(args, env);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
    defer file.close();
    return .nil;
}

fn appendHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = allocator;
    const parts = try expectTwoStrings(args, env);
    const file = try std.fs.cwd().openFile(parts[0], .{
        .mode = .write_only,
    });
    defer file.close();
    try file.writeAll(parts[1]);
    return .nil;
}
