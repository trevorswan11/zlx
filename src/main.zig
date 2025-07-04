const std = @import("std");

const parser = @import("parser/parser.zig");
const interpreter = @import("interpreter/interpreter.zig");
const syntax = @import("utils/syntax.zig");
const hex = @import("tooling/hex.zig");
const compression = @import("tooling/compression.zig");

const driver = @import("utils/driver.zig");
const getOrDispatchArgs = driver.getOrDispatchArgs;
const readFile = driver.readFile;

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

    const input = getOrDispatchArgs(allocator) catch |err| switch (err) {
        error.MalformedArgs => {
            try writer_err.print("Usage: zlx <run|ast|dump> <filepath> <time?> <-v?>\n", .{});
            return;
        },
        error.InternalDispatch => return,
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
    const file_contents = if (!input.archive and !input.de_archive and !input.compress and !input.decompress) blk: {
        break :blk readFile(allocator, input.path) catch |err| {
            try writer_err.print("Error reading file contents: {!}\n", .{err});
            parse = std.time.nanoTimestamp();
            if (input.time) {
                try writer_out.print("Timing:\n", .{});
                try writer_out.print("  Parsing failed in {d} ms\n", .{@as(f128, @floatFromInt(parse - start)) / 1_000_000.0});
            }
            return;
        };
    } else blk: {
        break :blk try std.fmt.allocPrint(allocator, "{s}", .{"NotRead"});
    };
    defer allocator.free(file_contents);
    args = std.time.nanoTimestamp();

    // Tooling
    if (input.compress or input.decompress or input.hex_dump or input.archive or input.de_archive) {
        const tool_start = std.time.nanoTimestamp();
        const tool_writer = if (input.file_out) |file_out| blk: {
            if (!input.de_archive) {
                const fo = try std.fs.cwd().createFile(file_out, .{});
                break :blk fo.writer().any();
            } else {
                break :blk writer_out;
            }
        } else blk: {
            break :blk writer_out;
        };

        var base_out_dir: std.fs.Dir = if (input.dir_out) |dir| blk: {
            if (input.force_dir_out) {
                try std.fs.cwd().deleteTree(dir);
            }

            try std.fs.cwd().makePath(dir);
            break :blk try std.fs.cwd().openDir(dir, .{
                .iterate = true,
            });
        } else if (input.file_out) |file_out| blk: {
            if (!input.de_archive) {
                break :blk std.fs.cwd();
            }

            if (input.force_dir_out) {
                try std.fs.cwd().deleteTree(file_out);
            }

            try std.fs.cwd().makePath(file_out);
            break :blk try std.fs.cwd().openDir(file_out, .{
                .iterate = true,
            });
        } else if (input.de_archive) {
            try writer_err.print("Output directory not specified for archive decompression.\n", .{});
            return;
        } else std.fs.cwd();
        defer base_out_dir.close();

        if (input.hex_dump) {
            try hex.dump(file_contents, tool_writer, writer_err);
        } else if (input.compress) {
            var file = try std.fs.cwd().openFile(input.path, .{
                .mode = .read_only,
            });
            try compression.compress(&file, tool_writer, writer_err);
        } else if (input.decompress) {
            var file = try std.fs.cwd().openFile(input.path, .{
                .mode = .read_only,
            });
            try compression.decompress(file.reader().any(), tool_writer, writer_err);
        } else if (input.archive) {
            var base_dir = try std.fs.cwd().openDir(input.path, .{ .iterate = true });
            defer base_dir.close();

            try compression.compressArchive(allocator, base_dir, tool_writer, writer_err);
        } else if (input.de_archive) {
            var file = try std.fs.cwd().openFile(input.path, .{
                .mode = .read_only,
            });

            try compression.decompressArchive(allocator, file.reader().any(), base_out_dir, writer_err);
        }
        const tool_end = std.time.nanoTimestamp();

        const arguments = @as(f128, @floatFromInt(args - start)) / 1_000_000.0;
        const elapsed = @as(f128, @floatFromInt(tool_end - tool_start)) / 1_000_000.0;
        const process = @as(f128, @floatFromInt(tool_end - start)) / 1_000_000.0;

        if (input.time) {
            try writer_out.print("Timing:\n", .{});
            try writer_out.print("  Args Parsing took: {d} ms\n", .{arguments});
            try writer_out.print("  {s} took: {d} ms\n", .{ input.tool_type, elapsed });
            try writer_out.print("  Process took: {d} ms\n", .{process});
        }
        return;
    }

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
        writer_out.print("{s}", .{try block.toString(allocator)}) catch |err| {
            try writer_err.print("Error parsing main block statement: {!}\n", .{err});
        };
    }

    // Successful parsing, so we can continue onto interpreting
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
    _ = @import("tests.zig");
}
