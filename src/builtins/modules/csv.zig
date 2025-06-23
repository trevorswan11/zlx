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
const expectArrayArgs = builtins.expectArrayArgs;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "read", readHandler);
    try pack(&map, "write", writeHandler);
    try pack(&map, "append", appendHandler);
    try pack(&map, "parse", parseHandler);
    try pack(&map, "stringify", stringifyHandler);

    return .{
        .object = map,
    };
}

fn readHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 1, "csv", "read");
    const filepath = parts[0];
    const contents = try std.fs.cwd().readFileAlloc(allocator, filepath, 1 << 20);
    defer allocator.free(contents);

    return try parseCSV(allocator, contents);
}

fn writeHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "csv", "write");
    const filepath = parts[0];
    const contents = try stringifyCSV(allocator, .{ .string = parts[1] });

    const dir_path = std.fs.path.dirname(filepath) orelse ".";
    try std.fs.cwd().makePath(dir_path);

    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();

    try file.writeAll(contents);
    return .nil;
}

fn appendHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const parts = try expectStringArgs(args, env, 2, "csv", "append");
    const filepath = parts[0];
    const contents = try stringifyCSV(allocator, .{ .string = parts[1] });

    const file = try std.fs.cwd().openFile(
        filepath,
        .{
            .mode = .write_only,
        },
    );
    defer file.close();

    try file.writeAll(contents);
    return .nil;
}

fn parseHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const input = try expectStringArgs(args, env, 1, "csv", "parse");
    return try parseCSV(allocator, input[0]);
}

fn stringifyHandler(allocator: std.mem.Allocator, args: []const *ast.Expr, env: *Environment) anyerror!Value {
    const input = (try expectArrayArgs(args, env, 1, "csv", "stringify"))[0];
    return .{
        .string = try stringifyCSV(allocator, .{ .array = input }),
    };
}

fn parseCSV(allocator: std.mem.Allocator, text: []const u8) !Value {
    var lines = std.mem.splitSequence(u8, text, "\n");

    var rows = std.ArrayList(Value).init(allocator);
    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t\r");
        if (trimmed_line.len == 0) {
            continue;
        }

        var fields = std.mem.splitAny(u8, trimmed_line, ",");
        var row = std.ArrayList(Value).init(allocator);
        while (fields.next()) |field| {
            const trimmed = std.mem.trim(u8, field, " \t\r");
            const str = try allocator.dupe(u8, trimmed);
            try row.append(.{
                .string = str,
            });
        }
        if (row.items.len == 0) {
            continue;
        }
        try rows.append(.{
            .array = row,
        });
    }

    return .{
        .array = rows,
    };
}

fn stringifyCSV(allocator: std.mem.Allocator, value: Value) ![]u8 {
    const writer_err = driver.getWriterErr();
    if (value != .array) {
        try writer_err.print("CSV stringify expects type array but found type {s}\n", .{@tagName(value)});
        return error.ExpectedArray;
    }

    const rows = value.array;
    var buf = std.ArrayList(u8).init(allocator);

    for (rows.items, 0..) |row_val, i| {
        if (row_val != .array) {
            try writer_err.print("CSV stringify expects nested arrays but found a(n) {s} at index {d}\n", .{ @tagName(row_val), i });
            return error.ExpectedNestedArray;
        }
        const row = row_val.array;

        for (row.items, 0..) |field_val, j| {
            switch (field_val) {
                .number, .boolean, .nil, .string => {
                    try buf.appendSlice(try field_val.toString(allocator));
                    if (j < row.items.len - 1) {
                        try buf.append(',');
                    }
                },
                else => {
                    try writer_err.print("Cannot stringify type {s} at index {d}\n", .{ @tagName(field_val), j });
                    return error.UnsupportedStringifyType;
                },
            }
        }
        try buf.append('\n');
    }

    return buf.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "csv_builtin" {
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

    const source =
        \\import csv;
        \\
        \\let text = ```a,b,c
        \\1,2,3```;
        \\let data = csv.parse(text);
        \\println(data);
        \\println(len(data));
        \\println(len(data[0]));
        \\println(data[0][0]);
        \\println(data[1][1]);
        \\let out = csv.stringify(data);
        \\print(out);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const expected =
        \\["["a", "b", "c"]", "["1", "2", "3"]"]
        \\2
        \\3
        \\a
        \\2
        \\a,b,c
        \\1,2,3
        \\
    ;

    try testing.expectEqualStrings(expected, output_buffer.items);
}
