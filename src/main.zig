const std = @import("std");

const parser = @import("parser/parser.zig");
const interpreter = @import("interpreter/environment.zig");
const syntax = @import("utils/syntax.zig");

const helpers = @import("utils/driver.zig");
const getArgs = helpers.getArgs;
const readFile = helpers.readFile;
const printStmt = helpers.printStmt;

pub fn main() !void {
    const t0 = std.time.nanoTimestamp();
    var t1: i128 = undefined;

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = getArgs(allocator) catch |err| switch (err) {
        error.MalformedArgs => {
            try stderr.print("Usage: zlx <run|ast|dump> <filepath> <time?> <-v?>\n", .{});
            return;
        },
        else => return,
    };

    // Gather the file contents
    const file_contents = readFile(allocator, input.path) catch |err| {
        try stderr.print("Error reading file contents: {!}\n", .{err});
        t1 = std.time.nanoTimestamp();
        if (input.time) {
            try stdout.print("Parsing failed in {d} ms\n", .{@as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0});
        }
        return;
    };
    defer allocator.free(file_contents);

    // Parse the file
    const block = parser.parse(allocator, file_contents) catch |err| switch (err) {
        else => {
            try stderr.print("Error parsing file: {!}\n", .{err});
            t1 = std.time.nanoTimestamp();
            if (input.time) {
                try stdout.print("Parsing failed in {d} ms\n", .{@as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0});
            }
            return;
        },
    };
    defer allocator.destroy(block);

    var env = interpreter.Environment.init(allocator, null);
    defer env.deinit();

    if (input.verbose) {
        try stdout.print("Dumping AST...\n", .{});
        printStmt(block, allocator) catch |err| {
            try stderr.print("Error parsing main block statement: {!}\n", .{err});
        };
    }

    // Successful parsing
    t1 = std.time.nanoTimestamp();
    if (input.time) {
        try stdout.print("Parsing took {d} ms\n", .{@as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0});
    }

    if (input.run) {
        try stdout.print("Evaluating Target...\n", .{});
        const number = interpreter.evalStmt(block, &env) catch |err| blk: {
            try stderr.print("Statement Evaluation Error: {!}\n", .{err});
            break :blk .nil;
        };
        try stdout.print("Statement Evaluation Result: {s}\n", .{try number.toString(allocator)});
    } else if (input.dump) {
        try stdout.print("Dumping file contents:\n", .{});
        try syntax.highlight(allocator, file_contents);
    } else {
        try stdout.print("Parsing completed without error\n", .{});
    }
}
