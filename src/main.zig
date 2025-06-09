const std = @import("std");

const parser = @import("parser/parser.zig");
const interpreter = @import("interpreter/interpreter.zig");
const syntax = @import("utils/syntax.zig");

const driver = @import("utils/driver.zig");
const getArgs = driver.getArgs;
const readFile = driver.readFile;
const printStmt = driver.printStmt;

pub fn main() !void {
    const t0 = std.time.nanoTimestamp();
    var t1: i128 = undefined;
    var t2: i128 = undefined;

    // Define stdout and stderr for output piping
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    interpreter.eval.setWriterOut(stdout.any());
    interpreter.eval.setWriterErr(stderr.any());

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

    // Enter repl mode if requested
    if (input.repl) {
        return try driver.startRepl(allocator);
    }

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
            try stderr.print("Error parsing file: {!}", .{err});
            t1 = std.time.nanoTimestamp();
            if (input.time) {
                try stdout.print("\nParsing failed in {d} ms", .{@as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0});
            }
            return;
        },
    };
    defer allocator.destroy(block);

    var env = interpreter.Environment.init(allocator, null);
    defer env.deinit();

    if (input.verbose) {
        if (input.dump) {
            try stdout.print("Dumping AST...\n", .{});
        }
        printStmt(block, allocator) catch |err| {
            try stderr.print("Error parsing main block statement: {!}\n", .{err});
        };
    }
    t1 = std.time.nanoTimestamp();

    // Successful parsing
    if (input.run) {
        if (input.verbose) {
            try stdout.print("Parsing completed without error\n", .{});
            try stdout.print("Evaluating target...\n", .{});
        }
        const number = interpreter.evalStmt(block, &env) catch |err| blk: {
            try stderr.print("Statement Evaluation Error: {!}\n", .{err});
            break :blk .nil;
        };
        if (number != .nil) {
            try stdout.print("Statement Evaluation Yielded: {s}\n", .{try number.toString(allocator)});
        }
    } else if (input.dump) {
        if (input.verbose) {
            try stdout.print("Dumping file contents...\n", .{});
        }
        try syntax.highlight(allocator, file_contents);
    } else {
        try stdout.print("Parsing completed without error", .{});
    }
    t2 = std.time.nanoTimestamp();
    if (input.time) {
        const parsing = @as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0;
        const interpreting = @as(f128, @floatFromInt(t2 - t1)) / 1_000_000.0;
        const process = @as(f128, @floatFromInt(t2 - t0)) / 1_000_000.0;
        if (input.run or input.dump) {
            try stdout.print("\n", .{});
        }
        try stdout.print("Timing:\n", .{});
        try stdout.print("  Parsing took:       {d} ms\n", .{parsing});
        try stdout.print("  Interpreting took:  {d} ms\n", .{interpreting});
        try stdout.print("  Process took:       {d} ms", .{process});
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

    // General Behavior - Tests located in `testing` directory
    _ = @import("testing/testing.zig");
    _ = @import("testing/classes_objects.zig");
    _ = @import("testing/functions.zig");
    _ = @import("testing/loops.zig");
    _ = @import("testing/operations.zig");
    _ = @import("testing/other.zig");
}
