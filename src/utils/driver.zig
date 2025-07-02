const std = @import("std");

const ast = @import("../parser/ast.zig");

fn toLower(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const lower = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }
    return lower;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) {
        return error.FileTooLarge;
    }

    const buffer = try allocator.alloc(u8, @intCast(stat.size));
    errdefer allocator.free(buffer);

    _ = try file.readAll(buffer);
    return buffer;
}

const Args = struct {
    path: []const u8 = "",
    time: bool = false,
    verbose: bool = false,
    run: bool = false,
    dump: bool = false,
    repl: bool = false,
    compress: bool = false,
    decompress: bool = false,
    hex_dump: bool = false,
    archive: bool = false,
    de_archive: bool = false,
    file_out: ?[]const u8 = null,
    dir_out: ?[]const u8 = null,
    force_dir_out: bool = false,
    tool_type: []const u8 = "",
};

/// Handles parsing the command line arguments for the process
pub fn getOrDispatchArgs(allocator: std.mem.Allocator) !Args {
    const writer_err = getWriterErr();
    var arguments = try std.process.argsWithAllocator(allocator);
    defer arguments.deinit();

    if (!arguments.skip()) {
        try writer_err.print("Usage: zlx <run|ast|dump> <filepath> <time?> <-v?>\n", .{});
        return error.InvalidUsage;
    }

    var path: ?[]const u8 = null;
    var time: bool = false;
    var verbose: bool = false;
    var run: bool = true;
    var dump: bool = false;
    var compress: bool = false;
    var decompress: bool = false;
    var hex_dump: bool = false;
    var archive: bool = false;
    var de_archive: bool = false;
    var file_out: ?[]const u8 = null;
    var dir_out: ?[]const u8 = null;
    var force_dir_out: bool = false;
    var tool_type: []const u8 = undefined;

    // The first arg can specify either run or ast, defaulting to run
    const raw_args = try std.process.argsAlloc(allocator);
    defer allocator.free(raw_args);

    if (raw_args.len == 1) {
        return .{
            .repl = true,
        };
    } else if (raw_args.len >= 3) optional_arg: {
        if (!isStringOneOfMany(raw_args[1], &[_][]const u8{
            "ast",
            "run",
            "dump",
            "compress",
            "-c",
            "decompress",
            "-dc",
            "hex",
            "-x",
            "archive",
            "-a",
            "dearchive",
            "-da",
            "-daf",
        })) {
            break :optional_arg;
        }

        if (arguments.next()) |next| {
            const r = try toLower(allocator, next);
            defer allocator.free(r);
            if (std.mem.eql(u8, r, "ast")) {
                run = false;
            } else if (std.mem.eql(u8, r, "run")) {
                run = true;
            } else if (std.mem.eql(u8, r, "dump")) {
                dump = true;
            } else if (std.mem.eql(u8, r, "compress") or std.mem.eql(u8, r, "-c")) {
                compress = true;
                tool_type = "Compression";
            } else if (std.mem.eql(u8, r, "decompress") or std.mem.eql(u8, r, "-dc")) {
                decompress = true;
                tool_type = "Decompression";
            } else if (std.mem.eql(u8, r, "hex") or std.mem.eql(u8, r, "-x")) {
                hex_dump = true;
                tool_type = "Hex Dumping";
            } else if (std.mem.eql(u8, r, "archive") or std.mem.eql(u8, r, "-a")) {
                archive = true;
                tool_type = "Archiving";
            } else if (std.mem.eql(u8, r, "dearchive") or std.mem.eql(u8, r, "-da")) {
                de_archive = true;
                tool_type = "De-archiving";
            } else if (std.mem.eql(u8, r, "-daf")) {
                de_archive = true;
                force_dir_out = true;
                tool_type = "De-archiving";
            } else {
                return error.InvalidRunTarget;
            }
        }
    }

    // Capture the mandatory filepath arg
    if (arguments.next()) |fp| blk: {
        const stat = std.fs.cwd().statFile(fp) catch |err| switch (err) {
            error.FileNotFound => {
                try writer_err.print("File not found in current working directory!\n", .{});
                return err;
            },
            error.IsDir => {
                if (compress or archive) {
                    // Dispatch dynamically, compression on folders calls archiving
                    compress = false;
                    archive = true;
                    tool_type = "Archiving";
                    path = fp;
                    break :blk;
                } else {
                    return err;
                }
            },
            else => return err,
        };
        if (stat.kind != .file) {
            try writer_err.print("Invalid file path!\n", .{});
            return error.InvalidFilename;
        }
        path = fp;
    }

    if (compress or decompress or hex_dump or archive or de_archive) blk: {
        if (raw_args.len >= 4) {
            const la = try toLower(allocator, raw_args[3]);
            defer allocator.free(la);
            if (std.mem.eql(u8, "time", la) or std.mem.eql(u8, "-v", la)) {
                break :blk;
            }
        }

        // Capture the output file for the tool
        if (!hex_dump and !de_archive) {
            if (arguments.next()) |out_file| {
                file_out = try allocator.dupe(u8, out_file);
            }
        } else if (!hex_dump and de_archive) {
            if (arguments.next()) |out_file| {
                if (force_dir_out) {
                    try std.fs.cwd().deleteTree(out_file);
                }
                try std.fs.cwd().makeDir(out_file);
                dir_out = try allocator.dupe(u8, out_file);
            }
        }
    }

    // Capture the optional time/bench arg
    while (arguments.next()) |next| {
        const flag = try toLower(allocator, next);
        defer allocator.free(flag);
        if (std.mem.eql(u8, flag, "time")) {
            time = true;
        } else if (std.mem.eql(u8, flag, "-v")) {
            verbose = true;
        } else {
            try writer_err.print("Unknown flag or too many arguments: {s}\n", .{flag});
            return error.InvalidUsage;
        }
    }

    if (path) |fp| {
        const basename = std.fs.path.basename(fp);
        if (run and std.mem.endsWith(u8, fp, "ast_check.zlx")) {
            try writer_err.print("You should not run this file! It is meant for ast checking ONLY\n", .{});
            return error.UseASTForMe;
        } else if ((compress or decompress or archive) and file_out == null) {
            const out_file = if (compress) blk: {
                break :blk try std.fmt.allocPrint(allocator, "{s}.zcx", .{basename});
            } else if (archive) blk: {
                break :blk try std.fmt.allocPrint(allocator, "{s}.zacx", .{basename});
            } else blk: {
                break :blk stripSuffix(basename, ".zcx");
            };

            if (std.mem.eql(u8, basename, out_file)) {
                try writer_err.print("Input filepath can not match output!\n", .{});
                return error.ImproperFilepath;
            }
            file_out = try allocator.dupe(u8, out_file);
        } else if (de_archive and dir_out == null) {
            dir_out = try allocator.dupe(u8, stripSuffix(basename, ".zacx"));
        }
        return .{
            .path = try allocator.dupe(u8, fp),
            .time = time,
            .verbose = verbose,
            .run = if (dump or compress or decompress or hex_dump) false else run,
            .dump = dump,
            .compress = compress,
            .decompress = decompress,
            .hex_dump = hex_dump,
            .archive = archive,
            .de_archive = de_archive,
            .tool_type = tool_type,
            .file_out = file_out,
            .force_dir_out = force_dir_out,
            .dir_out = dir_out,
        };
    } else return error.MalformedArgs;
}

pub fn isStringOneOfMany(string: []const u8, many: []const []const u8) bool {
    for (many) |compare| {
        if (std.mem.eql(u8, string, compare)) {
            return true;
        }
    }
    return false;
}

pub fn repl(allocator: std.mem.Allocator) !void {
    const eval = @import("../interpreter/eval.zig");
    const Environment = @import("../interpreter/interpreter.zig").Environment;

    const stdin = std.io.getStdIn().reader();
    const writer_out = getWriterOut();
    const writer_err = getWriterErr();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    try writer_out.print("Welcome to zlx REPL! Type 'exit' to quit.\n", .{});

    while (true) {
        try writer_out.print(">> ", .{});
        var full_line = std.ArrayList(u8).init(env.allocator);
        defer full_line.clearRetainingCapacity();

        while (true) {
            const line = try stdin.readUntilDelimiterOrEofAlloc(env.allocator, '\n', 1024) orelse {
                try writer_err.print("Input error!\n", .{});
                break;
            };

            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            if (std.mem.eql(u8, trimmed, "exit")) {
                return;
            } else if (std.mem.eql(u8, trimmed, "clenv")) {
                env.clear();
                break;
            }

            // Append the line
            try full_line.appendSlice(trimmed);

            // Check for continuation
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\\') {
                // Remove the backslash and continue reading
                _ = full_line.pop();
                try full_line.append(' ');
                try writer_out.print(".. ", .{});
                continue;
            }

            break;
        }

        const final_input = std.mem.trim(u8, full_line.items, " \t\r\n");
        if (final_input.len == 0) continue;

        const parser = @import("../parser/parser.zig");
        const block = parser.parseREPL(env.allocator, final_input) catch |err| {
            try writer_err.print("Parse Error: {!}\n", .{err});
            continue;
        };

        const result = eval.evalStmt(block, &env) catch |err| {
            try writer_err.print("Evaluation Error: {!}\n", .{err});
            continue;
        };

        if (result != .nil) {
            const result_str = try result.toString(env.allocator);
            try writer_out.print("{s}\n", .{result_str});
        }
    }
}

pub fn stripSuffix(s: []const u8, suffix: []const u8) []const u8 {
    if (s.len >= suffix.len and std.mem.endsWith(u8, s, suffix)) {
        return s[0 .. s.len - suffix.len];
    }
    return s;
}

pub fn toNullTerminatedString(allocator: std.mem.Allocator, input: []const u8) ![:0]const u8 {
    var buffer = try allocator.alloc(u8, input.len + 1);
    for (input, 0..) |c, i| {
        buffer[i] = c;
    }
    buffer[input.len] = 0;
    return buffer[0..input.len :0];
}

pub fn unescapeString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == '\\') {
            i += 1;
            if (i >= input.len) break;

            switch (input[i]) {
                'n' => try result.append('\n'),
                'r' => try result.append('\r'),
                't' => try result.append('\t'),
                '\\' => try result.append('\\'),
                '"' => try result.append('"'),
                '0' => try result.append(0),
                else => try result.append(input[i]),
            }
        } else {
            try result.append(input[i]);
        }
        i += 1;
    }

    return result.toOwnedSlice();
}

// === GLOBAL WRITER PIPING ===

pub var global_writer_out: ?std.io.AnyWriter = null;
pub var global_writer_err: ?std.io.AnyWriter = null;

pub fn setWriterOut(w: anytype) void {
    global_writer_out = w;
}

pub fn setWriterErr(w: anytype) void {
    global_writer_err = w;
}

pub fn setWriters(w: anytype) void {
    global_writer_out = w;
    global_writer_err = w;
}

pub fn getWriterOut() std.io.AnyWriter {
    return global_writer_out orelse return std.io.getStdOut().writer().any();
}

pub fn getWriterErr() std.io.AnyWriter {
    return global_writer_err orelse return std.io.getStdErr().writer().any();
}
