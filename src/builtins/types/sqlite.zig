const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const StdMethod = builtins.StdMethod;
const StdCtor = builtins.StdCtor;

// MACOS portability fix, pointer type '?*const fn (?*anyopaque) callconv(.c) void' requires aligned address
const sqlite3_destructor_type = ?*const fn (?*anyopaque) callconv(.C) void;
fn sqlite3_transient_dummy(_: ?*anyopaque) callconv(.C) void {}
const SQLITE_TRANSIENT = @as(sqlite3_destructor_type, @ptrCast(@alignCast(&sqlite3_transient_dummy)));

// general sql definition and usage

pub const SqliteInstance = struct {
    db: ?*c.sqlite3 = null,
};

fn getSqliteInstance(this: *Value) !*SqliteInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var SQLITE_METHODS: std.StringHashMap(StdMethod) = undefined;
var SQLITE_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    // SQL-only methods
    SQLITE_METHODS = std.StringHashMap(StdMethod).init(allocator);

    try SQLITE_METHODS.put("exec", sqliteExec);
    try SQLITE_METHODS.put("query", sqliteQuery);
    try SQLITE_METHODS.put("tables", sqliteTables);
    try SQLITE_METHODS.put("columns", sqliteColumns);
    try SQLITE_METHODS.put("close", sqliteClose);

    SQLITE_TYPE = .{
        .std_struct = .{
            .name = "sqlite",
            .constructor = sqliteConstructor,
            .methods = SQLITE_METHODS,
        },
    };

    // SQL-statement methods
    try SQLITE_METHODS.put("prepare", sqlitePrepare);

    STATEMENT_METHODS = std.StringHashMap(StdMethod).init(allocator);

    try STATEMENT_METHODS.put("bind", stmtBind);
    try STATEMENT_METHODS.put("bind_all", stmtBindAll);
    try STATEMENT_METHODS.put("step", stmtStep);
    try STATEMENT_METHODS.put("finalize", stmtFinalize);

    STATEMENT_TYPE = .{
        .std_struct = .{
            .name = "statement",
            .constructor = builtins.nullModuleFn,
            .methods = STATEMENT_METHODS,
        },
    };

    return SQLITE_TYPE;
}

fn sqliteConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    const val = (try builtins.expectStringArgs(args, env, 1, "sqlite", "ctor"))[0];
    const path = try env.allocator.dupeZ(u8, val);

    var db: ?*c.sqlite3 = null;
    const rc = c.sqlite3_open(path.ptr, &db);
    if (rc != c.SQLITE_OK) {
        try writer_err.print("sqlite open failed: {s}\n", .{c.sqlite3_errstr(rc)});
        return error.SqliteOpenFailed;
    }

    const wrapped = try env.allocator.create(SqliteInstance);
    wrapped.* = .{
        .db = db,
    };

    const internal = try env.allocator.create(Value);
    internal.* = .{
        .typed_val = .{
            ._type = "sqlite",
            .value = @ptrCast(@alignCast(wrapped)),
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = SQLITE_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn sqliteExec(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("sqlite.exec(sql) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = (try builtins.expectStringArgs(args, env, 1, "sqlite", "exec"))[0];
    const sql = try env.allocator.dupeZ(u8, val);
    const inst = try getSqliteInstance(this);

    const rc = c.sqlite3_exec(inst.db, sql.ptr, null, null, null);
    if (rc != c.SQLITE_OK) {
        try writer_err.print("sqlite.exec(sql) failed: {s}\n", .{c.sqlite3_errmsg(inst.db)});
        return error.SqliteExecFailed;
    }

    return .nil;
}

fn sqliteQuery(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("sqlite.query(sql) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = (try builtins.expectStringArgs(args, env, 1, "sqlite", "query"))[0];
    const sql = try env.allocator.dupeZ(u8, val);
    const inst = try getSqliteInstance(this);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc_prepare = c.sqlite3_prepare_v2(inst.db, sql, -1, &stmt, null);
    if (rc_prepare != c.SQLITE_OK) {
        try writer_err.print("sqlite.query(): prepare failed: {s}\n", .{c.sqlite3_errmsg(inst.db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = c.sqlite3_finalize(stmt);

    var rows = std.ArrayList(Value).init(env.allocator);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        var row = std.StringHashMap(Value).init(env.allocator);

        const column_count = c.sqlite3_column_count(stmt);
        var i: c_int = 0;
        while (i < column_count) : (i += 1) {
            const col_name_ptr = c.sqlite3_column_name(stmt, i);
            const col_slice = std.mem.span(col_name_ptr);
            const col_name = try env.allocator.dupe(u8, col_slice);

            const col_type = c.sqlite3_column_type(stmt, i);
            var nested_val: Value = .nil;

            switch (col_type) {
                c.SQLITE_INTEGER => {
                    nested_val = .{
                        .number = @floatFromInt(c.sqlite3_column_int64(stmt, i)),
                    };
                },
                c.SQLITE_FLOAT => {
                    nested_val = .{
                        .number = c.sqlite3_column_double(stmt, i),
                    };
                },
                c.SQLITE_TEXT => {
                    const text_ptr = c.sqlite3_column_text(stmt, i);
                    const text_len = c.sqlite3_column_bytes(stmt, i);
                    const slice = text_ptr[0..@intCast(text_len)];
                    nested_val = .{
                        .string = try env.allocator.dupe(u8, slice),
                    };
                },
                c.SQLITE_NULL => {
                    nested_val = .nil;
                },
                else => {
                    try writer_err.print("Unsupported column type in sqlite.query()\n", .{});
                    return error.UnsupportedColumnType;
                },
            }

            try row.put(col_name, nested_val);
        }

        try rows.append(.{
            .object = row,
        });
    }

    return .{
        .array = rows,
    };
}

fn sqliteTables(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("sqlite.tables() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getSqliteInstance(this);
    const sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(inst.db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        try writer_err.print("sqlite.tables() prepare failed: {s}\n", .{c.sqlite3_errmsg(inst.db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = c.sqlite3_finalize(stmt);

    var tables = std.ArrayList(Value).init(env.allocator);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const text_ptr = c.sqlite3_column_text(stmt, 0);
        const text_len = c.sqlite3_column_bytes(stmt, 0);
        const slice = text_ptr[0..@intCast(text_len)];
        const name = try env.allocator.dupe(u8, slice);
        try tables.append(.{ .string = name });
    }

    return .{
        .array = tables,
    };
}

fn sqliteColumns(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("sqlite.columns(table_name) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = (try builtins.expectStringArgs(args, env, 1, "sqlite", "columns"))[0];
    const table_name = try std.fmt.allocPrint(env.allocator, "PRAGMA table_info({s});", .{val});

    const inst = try getSqliteInstance(this);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(inst.db, table_name.ptr, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        try writer_err.print("sqlite.columns() prepare failed: {s}\n", .{c.sqlite3_errmsg(inst.db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = c.sqlite3_finalize(stmt);

    var columns = std.ArrayList(Value).init(env.allocator);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const text_ptr = c.sqlite3_column_text(stmt, 1);
        const text_len = c.sqlite3_column_bytes(stmt, 1);
        const slice = text_ptr[0..@intCast(text_len)];
        const name = try env.allocator.dupe(u8, slice);
        try columns.append(.{
            .string = name,
        });
    }

    return .{
        .array = columns,
    };
}

fn sqliteClose(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    if (args.len != 0) return error.ArgumentCountMismatch;
    const inst = try getSqliteInstance(this);

    if (inst.db) |db| {
        _ = c.sqlite3_close(db);
        inst.db = null;
    }
    return .nil;
}

// sql statement definition and usage

pub const StatementInstance = struct {
    stmt: ?*c.sqlite3_stmt = null,
    db: ?*c.sqlite3 = null,
};

fn getStmtInstance(this: *Value) !*StatementInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var STATEMENT_METHODS: std.StringHashMap(StdMethod) = undefined;
var STATEMENT_TYPE: Value = undefined;

/// Pseudo-load function for sql statements
fn sqlitePrepare(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("sqlite.prepare(sql) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = (try builtins.expectStringArgs(args, env, 1, "sqlite", "prepare"))[0];
    const sql = try env.allocator.dupeZ(u8, val);
    const db_inst = try getSqliteInstance(this);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(db_inst.db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        try writer_err.print("sqlite.prepare() failed: {s}\n", .{c.sqlite3_errmsg(db_inst.db)});
        return error.SqlitePrepareFailed;
    }

    const wrapped = try env.allocator.create(StatementInstance);
    wrapped.* = .{
        .stmt = stmt,
        .db = db_inst.db,
    };

    const internal = try env.allocator.create(Value);
    internal.* = .{
        .typed_val = .{
            ._type = "statement",
            .value = @ptrCast(@alignCast(wrapped)),
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = STATEMENT_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn stmtBind(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("statement.bind(val) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    const inst = try getStmtInstance(this);

    const index: c_int = 1;
    const rc = switch (val) {
        .number => c.sqlite3_bind_double(inst.stmt, index, val.number),
        .string => c.sqlite3_bind_text(inst.stmt, index, val.string.ptr, @intCast(val.string.len), SQLITE_TRANSIENT),
        .nil => c.sqlite3_bind_null(inst.stmt, index),
        else => {
            try writer_err.print("Unsupported bind value type\n", .{});
            return error.UnsupportedBindValue;
        },
    };

    if (rc != c.SQLITE_OK) {
        try writer_err.print("sqlite.bind() failed\n", .{});
        return error.SqliteBindFailed;
    }

    return .nil;
}

fn stmtBindAll(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (args.len != 1) {
        try writer_err.print("statement.bind_all(vals) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try eval.evalExpr(args[0], env);
    const inst = try getStmtInstance(this);

    if (val != .array) {
        try writer_err.print("bind_all() expects an array argument\n", .{});
        return error.TypeMismatch;
    }

    const vals = val.array.items;
    var i: usize = 0;
    while (i < vals.len) : (i += 1) {
        const index: c_int = @intCast(i + 1);
        const item = vals[i];

        const rc = switch (item) {
            .number => c.sqlite3_bind_double(inst.stmt, index, item.number),
            .string => c.sqlite3_bind_text(inst.stmt, index, item.string.ptr, @intCast(item.string.len), SQLITE_TRANSIENT),
            .nil => c.sqlite3_bind_null(inst.stmt, index),
            else => {
                try writer_err.print("Unsupported bind_all value at index {d}\n", .{i});
                return error.UnsupportedBindValue;
            },
        };

        if (rc != c.SQLITE_OK) {
            try writer_err.print("sqlite.bind_all() failed at index {d}\n", .{i});
            return error.SqliteBindFailed;
        }
    }

    return .nil;
}

fn stmtStep(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const inst = try getStmtInstance(this);
    const writer_err = driver.getWriterErr();

    if (args.len != 0) {
        try writer_err.print("statement.step() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const rc = c.sqlite3_step(inst.stmt);

    if (rc == c.SQLITE_ROW) {
        var row = std.StringHashMap(Value).init(env.allocator);
        const col_count = c.sqlite3_column_count(inst.stmt);
        var i: c_int = 0;
        while (i < col_count) : (i += 1) {
            const name_slice = std.mem.span(c.sqlite3_column_name(inst.stmt, i));
            const name = try env.allocator.dupe(u8, name_slice);
            const col_type = c.sqlite3_column_type(inst.stmt, i);

            const val: Value = switch (col_type) {
                c.SQLITE_INTEGER => .{
                    .number = @floatFromInt(c.sqlite3_column_int64(inst.stmt, i)),
                },
                c.SQLITE_FLOAT => .{
                    .number = c.sqlite3_column_double(inst.stmt, i),
                },
                c.SQLITE_TEXT => blk: {
                    const text_ptr = c.sqlite3_column_text(inst.stmt, i);
                    const text_len = c.sqlite3_column_bytes(inst.stmt, i);
                    const str = text_ptr[0..@intCast(text_len)];
                    break :blk .{
                        .string = try env.allocator.dupe(u8, str),
                    };
                },
                c.SQLITE_NULL => .nil,
                else => {
                    try writer_err.print("Unsupported column type\n", .{});
                    return error.UnsupportedColumnType;
                },
            };

            try row.put(name, val);
        }
        return .{ .object = row };
    } else if (rc == c.SQLITE_DONE) {
        return .nil;
    } else {
        try writer_err.print("sqlite.step() failed\n", .{});
        return error.SqliteStepFailed;
    }
}

fn stmtFinalize(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    if (args.len != 0) return error.ArgumentCountMismatch;
    const inst = try getStmtInstance(this);

    if (inst.stmt) |stmt| {
        _ = c.sqlite3_finalize(stmt);
        inst.stmt = null;
    }

    return .nil;
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "sqlite_base_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriterOut(writer);

    const source =
        \\import sqlite;
        \\import fs;
        \\
        \\let db = new sqlite("test.db");
        \\db.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER, name TEXT)");
        \\db.exec("INSERT INTO users VALUES (1, 'alice')");
        \\db.exec("INSERT INTO users VALUES (2, 'bob')");
        \\
        \\let rows = db.query("SELECT * FROM users");
        \\println(rows);
        \\
        \\let names = db.columns("users");
        \\println(names);
        \\
        \\let tables = db.tables();
        \\db.close();
        \\println(tables);
        \\
        \\fs.rm("test.db");
    ;

    const block = try testing.parse(allocator, try allocator.dupe(u8, source));
    _ = try interpreter.evalStmt(block, &env);

    const expected =
        \\["[obj]: {
        \\ id: 1
        \\ name: alice
        \\}", "[obj]: {
        \\ id: 2
        \\ name: bob
        \\}"]
        \\["id", "name"]
        \\["users"]
        \\
    ;

    try testing.expectEqualStrings(expected, output_buffer.items);
}

test "sqlite_stmt_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriterOut(writer);

    const stmt_test =
        \\import sqlite;
        \\import fs;
        \\
        \\let db = new sqlite("test2.db");
        \\db.exec("CREATE TABLE IF NOT EXISTS posts (id INTEGER, title TEXT)");
        \\
        \\let insert = db.prepare("INSERT INTO posts VALUES (?, ?)");
        \\insert.bind_all([10, "post1"]);
        \\insert.step();
        \\insert.finalize();
        \\
        \\let query = db.prepare("SELECT * FROM posts");
        \\let row = query.step();
        \\println(row);
        \\query.finalize();
        \\
        \\db.close();
        \\fs.rm("test2.db");
    ;

    const stmt_block = try testing.parse(allocator, try allocator.dupe(u8, stmt_test));
    _ = try interpreter.evalStmt(stmt_block, &env);

    const expected_stmt_output =
        \\[obj]: {
        \\ id: 10
        \\ title: post1
        \\}
        \\
    ;

    try testing.expectEqualStrings(expected_stmt_output, output_buffer.items);
}
