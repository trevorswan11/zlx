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
const expectStringArgs = builtins.expectStringArgs;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "read", readHandler);
    try pack(&map, "write", writeHandler);
    try pack(&map, "exists", existsHandler);
    try pack(&map, "remove", removeHandler);
    try pack(&map, "list", listHandler);
    try pack(&map, "mkdir", mkdirHandler);
    try pack(&map, "rmdir", rmdirHandler);
    try pack(&map, "rm", rmHandler);
    try pack(&map, "copy", copyHandler);
    try pack(&map, "rename", renameHandler);
    try pack(&map, "is_dir", isDirHandler);
    try pack(&map, "read_lines", readLinesHandler);
    try pack(&map, "touch", touchHandler);
    try pack(&map, "append", appendHandler);
    try pack(&map, "list_all_files", listAllFilesHandler);

    return .{
        .object = map,
    };
}

fn readHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "read"))[0];
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    return .{
        .string = contents,
    };
}

pub fn writeHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "fs", "write");
    const full_path = parts[0];

    const dir_path = std.fs.path.dirname(full_path) orelse ".";
    try std.fs.cwd().makePath(dir_path);

    const file = try std.fs.cwd().createFile(full_path, .{});
    defer file.close();

    try file.writeAll(parts[1]);
    return .nil;
}

pub fn existsHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "exists"))[0];
    std.fs.cwd().access(path, .{}) catch {
        return .{
            .boolean = false,
        };
    };

    return .{
        .boolean = true,
    };
}

fn removeHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "remove"))[0];
    try std.fs.cwd().deleteFile(path);

    return .nil;
}

fn listHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "list"))[0];
    var dir = try std.fs.cwd().openDir(
        path,
        .{
            .iterate = true,
        },
    );
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

        try array.append(
            .{
                .string = name,
            },
        );
    }

    return .{
        .array = array,
    };
}

fn mkdirHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "mkdir"))[0];
    try std.fs.cwd().makeDir(path);
    return .nil;
}

fn rmdirHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "rmdir"))[0];
    try std.fs.cwd().deleteDir(path);
    return .nil;
}

fn rmHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "rm"))[0];
    try std.fs.cwd().deleteTree(path);
    return .nil;
}

fn copyHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const writer_err = driver.getWriterErr();
    const parts = try expectStringArgs(args, env, 2, "fs", "copy");
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
        try writer_err.print("Could not find file {s} to copy\n", .{src_path});
        return error.FileNotFound;
    };

    cwd.makePath(dst_dir_path) catch {
        try writer_err.print("Could not create directory {s}\n", .{dst_dir_path});
        return error.DirectoryCreationError;
    };

    var dst_dir = try cwd.openDir(dst_dir_path, .{});
    defer dst_dir.close();

    try src_dir.copyFile(src_basename, dst_dir, dst_basename, .{});

    return .nil;
}

fn renameHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "fs", "rename");
    try std.fs.cwd().rename(parts[0], parts[1]);
    return .nil;
}

fn isDirHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "is_dir"))[0];
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return .{
            .boolean = false,
        };
    };
    dir.close();
    return .{
        .boolean = true,
    };
}

fn readLinesHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "read_lines"))[0];
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader = std.io.bufferedReader(file.reader());
    var buf = reader.reader();
    var lines = std.ArrayList(Value).init(allocator);

    while (try buf.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096)) |line| {
        try lines.append(
            .{
                .string = line,
            },
        );
    }

    return .{
        .array = lines,
    };
}

fn touchHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const path = (try expectStringArgs(args, env, 1, "fs", "touch"))[0];
    const file = try std.fs.cwd().createFile(
        path,
        .{
            .truncate = false,
        },
    );
    defer file.close();
    return .nil;
}

fn appendHandler(_: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "fs", "append");
    const file = try std.fs.cwd().openFile(
        parts[0],
        .{
            .mode = .write_only,
        },
    );
    defer file.close();
    try file.writeAll(parts[1]);
    return .nil;
}

fn listAllFilesHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const start_path = (try expectStringArgs(args, env, 1, "fs", "list_all_files"))[0];
    var result = std.ArrayList(Value).init(allocator);

    const cwd = std.fs.cwd();
    try recurseDir(cwd, start_path, allocator, &result);

    return .{
        .array = result,
    };
}

fn recurseDir(
    parent_dir: std.fs.Dir,
    path: []const u8,
    allocator: std.mem.Allocator,
    out_list: *std.ArrayList(Value),
) anyerror!void {
    var dir = try parent_dir.openDir(path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &.{ path, entry.name });

        switch (entry.kind) {
            .file => {
                try out_list.append(.{ .string = full_path });
            },
            .directory => {
                if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
                    continue;
                }
                try recurseDir(parent_dir, full_path, allocator, out_list);
            },
            else => {},
        }
    }
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "fs_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriters(writer);

    const path: []const u8 = &tmp_dir.sub_path;
    errdefer {
        var exists = true;
        std.fs.cwd().access(path, .{}) catch {
            exists = false;
        };
        if (exists) {
            std.fs.cwd().deleteTree(path) catch {};
        }
    }

    const source = try std.fmt.allocPrint(allocator,
        \\import fs;
        \\
        \\const p = "{s}";
        \\
        \\fs.write(p + "/example.txt", "hello world");
        \\println(fs.exists(p + "/example.txt"));
        \\println(fs.read(p + "/example.txt"));
        \\
        \\fs.copy(p + "/example.txt", p + "/example_copy.txt");
        \\println(fs.exists(p + "/example_copy.txt"));
        \\
        \\fs.rename(p + "/example_copy.txt", p + "/example_renamed.txt");
        \\println(fs.exists(p + "/example_copy.txt"));
        \\println(fs.exists(p + "/example_renamed.txt"));
        \\
        \\fs.mkdir(p + "/test_dir");
        \\fs.write(p + "/test_dir/file.txt", "hi");
        \\let items = fs.list(p + "/test_dir");
        \\println(items);
        \\
        \\println(fs.is_dir(p + "/test_dir"));
        \\println(fs.is_dir(p + "/example.txt"));
        \\
        \\fs.remove(p + "/example.txt");
        \\fs.remove(p + "/example_renamed.txt");
        \\fs.remove(p + "/test_dir/file.txt");
        \\println(fs.exists(p + "/example.txt"));
        \\fs.rm(p);
    , .{path});

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected = try std.fmt.allocPrint(allocator,
        \\true
        \\hello world
        \\true
        \\false
        \\true
        \\["file.txt"]
        \\true
        \\false
        \\false
        \\
    , .{});

    try testing.expectEqualStrings(expected, output_buffer.items);
}
