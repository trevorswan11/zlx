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
    const buffer = try allocator.alloc(u8, stat.size);
    _ = try file.readAll(buffer);
    return buffer;
}

const Args = struct {
    path: []const u8 = "",
    time: bool = false,
    verbose: bool = false,
    run: bool = true,
    dump: bool = false,
    repl: bool = false,
};

/// Handles parsing the command line arguments for the process
pub fn getArgs(allocator: std.mem.Allocator) !Args {
    const writer_err = getWriterErr();
    var arguments = try std.process.argsWithAllocator(allocator);
    defer arguments.deinit();

    if (!arguments.skip()) {
        try writer_err.print("Usage: zlx <run|ast> <filepath> <time?> <-v?>\n", .{});
        return error.InvalidUsage;
    }

    var filepath: ?[]const u8 = null;
    var time: bool = false;
    var verbose: bool = false;
    var run: bool = true;
    var dump: bool = false;

    // The first arg can specify either run or ast, defaulting to run
    const raw_args = try std.process.argsAlloc(allocator);
    defer allocator.free(raw_args);

    if (raw_args.len == 1) {
        return .{
            .repl = true,
        };
    } else if (raw_args.len >= 3) optional_arg: {
        if (!std.mem.eql(u8, raw_args[1], "ast") and !std.mem.eql(u8, raw_args[1], "run") and !std.mem.eql(u8, raw_args[1], "dump")) {
            break :optional_arg;
        }

        if (arguments.next()) |r| {
            if (std.mem.eql(u8, r, "ast")) {
                run = false;
            } else if (std.mem.eql(u8, r, "run")) {
                run = true;
            } else if (std.mem.eql(u8, r, "dump")) {
                dump = true;
            } else {
                return error.InvalidRunTarget;
            }
        }
    }

    // Capture the mandatory filepath arg
    if (arguments.next()) |fp| {
        const stat = std.fs.cwd().statFile(fp) catch |err| switch (err) {
            error.FileNotFound => {
                try writer_err.print("File not found in current working directory!\n", .{});
                return err;
            },
            else => return err,
        };
        if (stat.kind != .file) {
            try writer_err.print("Invalid file path!\n", .{});
            return error.InvalidFilename;
        }
        filepath = fp;
    }

    // Capture the optional time/bench arg
    if (arguments.next()) |next| {
        const flag = try toLower(allocator, next);
        defer allocator.free(flag);
        if (std.mem.eql(u8, flag, "time")) {
            time = true;
            if (arguments.next()) |v| {
                const v_flag = try toLower(allocator, v);
                defer allocator.free(v_flag);
                verbose = std.mem.eql(u8, v_flag, "-v");
            }
        } else if (std.mem.eql(u8, flag, "-v")) {
            verbose = true;
            if (arguments.next()) |t| {
                const t_flag = try toLower(allocator, t);
                defer allocator.free(t_flag);
                time = std.mem.eql(u8, t_flag, "time");
            }
        }
    }

    if (filepath) |fp| {
        if (run and std.mem.endsWith(u8, fp, "ast_check.zlx")) {
            try writer_err.print("You should not run this file! It is meant for ast checking ONLY\n", .{});
            return error.UseASTForMe;
        }
        return .{
            .path = try allocator.dupe(u8, fp),
            .time = time,
            .verbose = verbose,
            .run = if (!dump) run else false,
            .dump = dump,
        };
    } else return error.MalformedArgs;
}

pub fn printStmt(stmt: *ast.Stmt, allocator: std.mem.Allocator) !void {
    const writer = getWriterOut();
    for (stmt.block.body.items) |s| {
        switch (s.*) {
            .block => {
                try writer.print("Block Statement\n", .{});
                for (s.block.body.items) |it| {
                    const str = try it.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
            },
            .class_decl => {
                try writer.print("Class Declaration Statement: Name = {s}\n", .{s.class_decl.name});
                for (s.class_decl.body.items) |it| {
                    const str = try it.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
            },
            .expression => {
                try writer.print("Expression Statement\n", .{});
                const str = try s.expression.expression.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
            .foreach_stmt => {
                try writer.print("Foreach Statement\n", .{});
                for (s.foreach_stmt.body.items) |it| {
                    const str = try it.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
                try writer.print("Value: {s}\n", .{s.foreach_stmt.value});
                try writer.print("Index: {s}\n", .{if (s.foreach_stmt.index) "true" else "false"});
                const str = try s.foreach_stmt.iterable.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
            .while_stmt => {
                try writer.print("While Statement\n", .{});
                for (s.while_stmt.body.items) |it| {
                    const str = try it.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
                try writer.print("Condition:\n", .{});
                const str = try s.while_stmt.condition.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
            .function_decl => {
                try writer.print("Function Declaration Statement: Name = {s}\n", .{s.function_decl.name});
                for (s.function_decl.body.items) |it| {
                    const str = try it.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
                try writer.print("{d} Parameter(s)\n", .{s.function_decl.parameters.items.len});
                for (s.function_decl.parameters.items) |it| {
                    const str = try it.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
                try writer.print("Return type: ", .{});
                const str = try s.function_decl.return_type.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
            .if_stmt => {
                try writer.print("If Statement\n", .{});
                try writer.print("Condition: ", .{});
                const str_cond = try s.if_stmt.condition.toString(allocator);
                defer allocator.free(str_cond);
                try writer.print("{s}\n", .{str_cond});
                if (s.if_stmt.alternate) |alt| {
                    try writer.print("Alternate: ", .{});
                    const str = try alt.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
                try writer.print("Consequent: ", .{});
                const str = try s.if_stmt.consequent.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
            .import_stmt => {
                try writer.print("Import Statement\n", .{});
                try writer.print("Name: {s} -- From {s}\n", .{ s.import_stmt.name, s.import_stmt.from });
            },
            .var_decl => {
                try writer.print("Variable Declaration Statement: Identifier = {s}\n", .{s.var_decl.identifier});
                try writer.print("Constant: {s}\n", .{if (s.var_decl.constant) "true" else "false"});
                if (s.var_decl.explicit_type) |et| {
                    try writer.print("Explicit Type: ", .{});
                    const str = try et.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
                if (s.var_decl.assigned_value) |av| {
                    try writer.print("Assigned Value: ", .{});
                    const str = try av.toString(allocator);
                    defer allocator.free(str);
                    try writer.print("{s}\n", .{str});
                }
            },
            .break_stmt => {
                try writer.print("break\n", .{});
            },
            .continue_stmt => {
                try writer.print("continue\n", .{});
            },
            .return_stmt => {
                try writer.print("Return: ", .{});
                const str = try s.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
            .match_stmt => {
                try writer.print("Match: ", .{});
                const str = try s.toString(allocator);
                defer allocator.free(str);
                try writer.print("{s}\n", .{str});
            },
        }
    }
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
