const std = @import("std");

const parser = @import("parser/parser.zig");
const interpreter = @import("interpreter/interpreter.zig");
const syntax = @import("utils/syntax.zig");

const driver = @import("utils/driver.zig");
const getArgs = driver.getArgs;
const readFile = driver.readFile;
const printStmt = driver.printStmt;

pub fn main() !void {
    const start = std.time.nanoTimestamp();
    var args: i128 = undefined;
    var parse: i128 = undefined;
    var work: i128 = undefined;

    // Define stdout and stderr for output piping
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    driver.setWriterOut(stdout.any());
    driver.setWriterErr(stderr.any());
    const writer_out = driver.getWriterOut();
    const writer_err = driver.getWriterErr();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = getArgs(allocator) catch |err| switch (err) {
        error.MalformedArgs => {
            try writer_err.print("Usage: zlx <run|ast|dump> <filepath> <time?> <-v?>\n", .{});
            return;
        },
        else => {
            try writer_err.print("Error parsing command line args: {!}\n", .{err});
            return;
        },
    };

    // Enter repl mode if requested
    if (input.repl) {
        return try driver.repl(allocator);
    }

    // Gather the file contents
    const file_contents = readFile(allocator, input.path) catch |err| {
        try writer_err.print("Error reading file contents: {!}\n", .{err});
        parse = std.time.nanoTimestamp();
        if (input.time) {
            try writer_out.print("Parsing failed in {d} ms\n", .{@as(f128, @floatFromInt(parse - start)) / 1_000_000.0});
        }
        return;
    };
    defer allocator.free(file_contents);
    args = std.time.nanoTimestamp();

    // Parse the file
    const block = parser.parse(allocator, file_contents) catch |err| switch (err) {
        else => {
            try writer_err.print("Error parsing file: {!}", .{err});
            parse = std.time.nanoTimestamp();
            if (input.time) {
                try writer_out.print("\nParsing failed in {d} ms", .{@as(f128, @floatFromInt(parse - start)) / 1_000_000.0});
            }
            return;
        },
    };
    defer allocator.destroy(block);
    parse = std.time.nanoTimestamp();

    if (input.verbose) {
        if (input.dump) {
            try writer_out.print("Dumping AST...\n", .{});
        }
        printStmt(block, allocator) catch |err| {
            try writer_err.print("Error parsing main block statement: {!}\n", .{err});
        };
    }

    // Successful parsing
    var env = interpreter.Environment.init(allocator, null);
    defer env.deinit();

    if (input.run) {
        if (input.verbose) {
            try writer_out.print("Parsing completed without error\n", .{});
            try writer_out.print("Evaluating target...\n", .{});
        }
        const number = interpreter.evalStmt(block, &env) catch |err| blk: {
            try writer_err.print("Statement Evaluation Error: {!}\n", .{err});
            break :blk .nil;
        };
        if (number != .nil) {
            try writer_out.print("Statement Evaluation Yielded: {s}\n", .{try number.toString(allocator)});
        }
    } else if (input.dump) {
        if (input.verbose) {
            try writer_out.print("Dumping file contents...\n", .{});
        }
        try syntax.highlight(allocator, file_contents);
    } else {
        try writer_out.print("Parsing completed without error", .{});
    }
    work = std.time.nanoTimestamp();
    if (input.time) {
        const arguments = @as(f128, @floatFromInt(args - start)) / 1_000_000.0;
        const parsing = @as(f128, @floatFromInt(parse - args)) / 1_000_000.0;
        const working = @as(f128, @floatFromInt(work - parse)) / 1_000_000.0;
        const process = @as(f128, @floatFromInt(work - start)) / 1_000_000.0;
        if (input.run or input.dump) {
            try writer_out.print("\n", .{});
        }
        try writer_out.print("Timing:\n", .{});
        try writer_out.print("  Args Parsing took:   {d} ms\n", .{arguments});
        try writer_out.print("  File Parsing took:   {d} ms\n", .{parsing});
        if (input.run) {
            try writer_out.print("  Interpreting took:   {d} ms\n", .{working});
        }
        if (input.verbose) {
            try writer_out.print("  Verbose dump took:   {d} ms\n", .{working});
        } else if (input.dump) {
            try writer_out.print("  Syntax dump took:    {d} ms\n", .{working});
        }
        try writer_out.print("  Full Process took:   {d} ms", .{process});
    }
}

test {
    // Builtin Modules - Tests located with source code
    _ = @import("builtins/fns.zig");
    _ = @import("builtins/modules/array.zig");
    _ = @import("builtins/modules/debug.zig");
    _ = @import("builtins/modules/fs.zig");
    _ = @import("builtins/modules/math.zig");
    _ = @import("builtins/modules/path.zig");
    _ = @import("builtins/modules/random.zig");
    _ = @import("builtins/modules/string.zig");
    _ = @import("builtins/modules/sys.zig");
    _ = @import("builtins/modules/time.zig");
    _ = @import("builtins/modules/csv.zig");
    _ = @import("builtins/modules/json.zig");

    // General Behavior - Tests located in `testing` directory
    _ = @import("testing/testing.zig");
    _ = @import("testing/structs_objects.zig");
    _ = @import("testing/functions.zig");
    _ = @import("testing/loops.zig");
    _ = @import("testing/operations.zig");
    _ = @import("testing/other.zig");
}
