const std = @import("std");

const ast = @import("../parser/ast.zig");
const environment = @import("environment.zig");
const builtins = @import("../builtins/builtins.zig");

const Environment = environment.Environment;
const Value = environment.Value;

const evalBinary = @import("eval.zig").evalBinary;
const evalExpr = @import("eval.zig").evalExpr;
const evalStmt = @import("eval.zig").evalStmt;

pub fn variable(v: *ast.VarDeclarationStmt, env: *Environment) !Value {
    const val: Value = if (v.assigned_value) |a| try evalExpr(a, env) else .nil;
    try env.define(v.identifier, val);
    return .nil;
}

pub fn expression(e: *ast.ExpressionStmt, env: *Environment) !Value {
    return try evalExpr(e.expression, env);
}

pub fn block(b: *ast.BlockStmt, env: *Environment) !Value {
    var last: Value = .nil;
    for (b.body.items) |s| {
        last = try evalStmt(s, env);
    }
    return last;
}

pub fn conditional(i: *ast.IfStmt, env: *Environment) !Value {
    const cond = try evalExpr(i.condition, env);
    if (cond != Value.boolean) return error.TypeMismatch;

    if (cond.boolean) {
        return try evalStmt(i.consequent, env);
    } else if (i.alternate) |alt| {
        return try evalStmt(alt, env);
    } else {
        return .nil;
    }
}

pub fn foreach(f: *ast.ForeachStmt, env: *Environment) !Value {
    const iterable = try evalExpr(f.iterable, env);
    if (iterable != Value.array) return error.TypeMismatch;

    for (iterable.array.items, 0..) |item, i| {
        var child_env = Environment.init(env.allocator, env);
        try child_env.define(f.value, item);
        if (f.index) {
            try child_env.define("index", Value{
                .number = @floatFromInt(i),
            });
        }

        for (f.body.items) |parsed| {
            _ = try evalStmt(parsed, &child_env);
        }
    }

    return .nil;
}

pub fn while_loop(w: *ast.WhileStmt, env: *Environment) !Value {
    while (true) {
        const cond = try evalExpr(w.condition, env);
        if (cond != .boolean) {
            return error.TypeMismatch;
        }
        if (!cond.boolean) {
            break;
        }

        for (w.body.items) |stmt| {
            _ = try evalStmt(stmt, env);
        }
    }

    return .nil;
}

pub fn class(c: *ast.ClassDeclarationStmt, env: *Environment) !Value {
    var methods = std.StringHashMap(*ast.Stmt).init(env.allocator);
    var constructor: ?*ast.Stmt = null;

    for (c.body.items) |statement| {
        if (statement.* == .function_decl) {
            const fn_decl = statement.function_decl;
            if (std.mem.eql(u8, fn_decl.name, "ctor")) {
                constructor = statement;
            } else {
                try methods.put(fn_decl.name, statement);
            }
        }
    }

    const cls_val = Value{
        .class = .{
            .name = c.name,
            .body = c.body,
            .constructor = constructor,
            .methods = methods,
        },
    };
    try env.define(c.name, cls_val);
    return .nil;
}

pub fn function(f: *ast.FunctionDeclarationStmt, env: *Environment) !Value {
    const param_names = try env.allocator.alloc([]const u8, f.parameters.items.len);
    for (f.parameters.items, 0..) |p, i| {
        param_names[i] = p.name;
    }

    const func_val = Value{
        .function = .{
            .parameters = param_names,
            .body = f.body,
            .closure = env,
        },
    };

    try env.define(f.name, func_val);
    return .nil;
}

pub fn import(i: *ast.ImportStmt, env: *Environment) !Value {
    const allocator = env.allocator;
    for (builtins.builtin_modules) |builtin| {
        if (std.mem.eql(u8, builtin.name, i.from)) {
            const module_value = try builtin.loader(allocator);
            try env.define(i.name, module_value);
            return .nil;
        }
    }

    const path = i.from;
    const stderr = std.io.getStdErr().writer();

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try stderr.print("Error Opening Import: {s} from {s}\n", .{ i.name, i.from });
        try stderr.print("{!}\n", .{err});
        return err;
    };
    defer file.close();

    // Parse the file using our parser, 10 MB max file size
    const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);

    const parser = @import("../parser/parser.zig");
    const parse = parser.parse;

    const ast_block = try parse(allocator, contents);

    return try evalStmt(ast_block, env);
}
