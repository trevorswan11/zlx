const std = @import("std");
const ast = @import("ast/ast.zig");

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
    path: []const u8,
    time: bool,
    verbose: bool = false,
    run: bool,
};

/// Handles parsing the command line arguments for the process
pub fn getArgs(allocator: std.mem.Allocator) !Args {
    const stderr = std.io.getStdErr().writer();
    var arguments = try std.process.argsWithAllocator(allocator);
    defer arguments.deinit();

    if (!arguments.skip()) {
        try stderr.print("Usage: zlx <run|ast> <filepath> <time?> <-v?>\n", .{});
        return error.InvalidUsage;
    }

    var filepath: ?[]const u8 = null;
    var time: bool = false;
    var verbose: bool = false;
    var run: bool = true;

    // The first arg can specify either run or ast, defaulting to run
    const raw_args = try std.process.argsAlloc(allocator);
    defer allocator.free(raw_args);
    if (raw_args.len == 3) {
        if (arguments.next()) |r| {
            if (std.mem.eql(u8, r, "ast")) {
                run = false;
            } else if (std.mem.eql(u8, r, "run")) {
                run = true;
            } else {
                return error.InvalidRunTarget;
            }
        }
    }

    // Capture the mandatory filepath arg
    if (arguments.next()) |fp| {
        const stat = std.fs.cwd().statFile(fp) catch |err| switch (err) {
            error.FileNotFound => {
                try stderr.print("File not found in current working directory!\n", .{});
                return err;
            },
            else => return err,
        };
        if (stat.kind != .file) {
            try stderr.print("Invalid file path!\n", .{});
            return error.InvalidFilename;
        }
        filepath = fp;
    }

    // Capture the optional time/bench arg
    if (arguments.next()) |next| {
        const t_flag = try toLower(allocator, next);
        defer allocator.free(t_flag);
        if (std.mem.eql(u8, t_flag, "time")) {
            time = true;
            if (arguments.next()) |v| {
                const v_flag = try toLower(allocator, v);
                defer allocator.free(v_flag);
                verbose = std.mem.eql(u8, v_flag, "-v");
            }
        } else {
            const v_flag = try toLower(allocator, next);
            defer allocator.free(v_flag);
            verbose = std.mem.eql(u8, v_flag, "-v");
        }
    }

    if (filepath) |fp| {
        return Args{
            .path = try allocator.dupe(u8, fp),
            .time = time,
            .verbose = verbose,
            .run = run,
        };
    } else return error.MalformedArgs;
}

pub fn printStmt(stmt: *ast.Stmt) !void {
    const stdout = std.io.getStdOut().writer();
    for (stmt.block.body.items) |s| {
        switch (s.*) {
            .block => {
                try stdout.print("Block Statement\n", .{});
                for (s.block.body.items) |it| {
                    try it.print();
                }
                try stdout.print("\n", .{});
            },
            .class_decl => {
                try stdout.print("Class Declaration Statement: Name = {s}\n", .{s.class_decl.name});
                for (s.class_decl.body.items) |it| {
                    try it.print();
                }
                try stdout.print("\n", .{});
            },
            .expression => {
                try stdout.print("Expression Statement\n", .{});
                try s.expression.expression.print();
                try stdout.print("\n", .{});
            },
            .foreach_stmt => {
                try stdout.print("Foreach Statement\n", .{});
                for (s.foreach_stmt.body.items) |it| {
                    try it.print();
                }
                try stdout.print("Value: {s}\n", .{s.foreach_stmt.value});
                try stdout.print("Index: {s}\n", .{if (s.foreach_stmt.index) "true" else "false"});
                try s.foreach_stmt.iterable.print();
                try stdout.print("\n", .{});
            },
            .while_stmt => {
                try stdout.print("While Statement\n", .{});
                for (s.while_stmt.body.items) |it| {
                    try it.print();
                }
                try stdout.print("Condition:\n", .{});
                try s.while_stmt.condition.print();
                try stdout.print("\n", .{});
            },
            .function_decl => {
                try stdout.print("Function Declaration Statement: Name = {s}\n", .{s.function_decl.name});
                for (s.function_decl.body.items) |it| {
                    try it.print();
                }
                try stdout.print("{d} Parameter(s)\n", .{s.function_decl.parameters.items.len});
                for (s.function_decl.parameters.items) |it| {
                    try it.print();
                }
                try stdout.print("Return type: ", .{});
                try s.function_decl.return_type.print();
                try stdout.print("\n", .{});
            },
            .if_stmt => {
                try stdout.print("If Statement\n", .{});
                try stdout.print("Condition: ", .{});
                try s.if_stmt.condition.print();
                if (s.if_stmt.alternate) |alt| {
                    try stdout.print("Alternate: ", .{});
                    try alt.print();
                }
                try stdout.print("Consequent: ", .{});
                try s.if_stmt.consequent.print();
                try stdout.print("\n", .{});
            },
            .import_stmt => {
                try stdout.print("Import Statement\n", .{});
                try stdout.print("Name: {s} -- From {s}\n", .{ s.import_stmt.name, s.import_stmt.from });
                try stdout.print("\n", .{});
            },
            .var_decl => {
                try stdout.print("Variable Declaration Statement: Identifier = {s}\n", .{s.var_decl.identifier});
                try stdout.print("Constant: {s}\n", .{if (s.var_decl.constant) "true" else "false"});
                if (s.var_decl.explicit_type) |et| {
                    try stdout.print("Explicit Type: ", .{});
                    try et.print();
                }
                if (s.var_decl.assigned_value) |av| {
                    try stdout.print("Assigned Value: ", .{});
                    try av.print();
                }
                try stdout.print("\n", .{});
            },
        }
    }
}
