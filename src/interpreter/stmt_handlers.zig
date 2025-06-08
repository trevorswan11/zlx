const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("interpreter.zig");
const builtins = @import("../builtins/builtins.zig");
const eval = @import("eval.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const evalBinary = eval.evalBinary;
const evalExpr = eval.evalExpr;
const evalStmt = eval.evalStmt;

pub fn variable(v: *ast.VarDeclarationStmt, env: *Environment) !Value {
    const val: Value = if (v.assigned_value) |a| try evalExpr(a, env) else .nil;
    if (v.explicit_type) |t| {
        const value_ptr = try env.allocator.create(Value);
        value_ptr.* = val;
        switch (t.*) {
            .symbol => |s| {
                const to_put: Value = .{
                    .typed_val = .{
                        .value = value_ptr,
                        .type = s.value_type,
                    },
                };
                if (v.constant) {
                    try env.defineConstant(v.identifier, to_put);
                } else {
                    try env.define(v.identifier, to_put);
                }
                return .nil;
            },
            .list => |l| {
                const type_str = try l.underlying.toString(env.allocator);
                const to_put: Value = .{
                    .typed_val = .{
                        .value = value_ptr,
                        .type = type_str,
                    },
                };
                if (v.constant) {
                    try env.defineConstant(v.identifier, to_put);
                } else {
                    try env.define(v.identifier, to_put);
                }
                return .nil;
            },
        }
    }
    if (v.constant) {
        try env.defineConstant(v.identifier, val);
    } else {
        try env.define(v.identifier, val);
    }
    return .nil;
}

pub fn expression(e: *ast.ExpressionStmt, env: *Environment) !Value {
    return try evalExpr(e.expression, env);
}

pub fn block(b: *ast.BlockStmt, env: *Environment) !Value {
    var last: Value = .nil;
    for (b.body.items) |s| {
        last = try evalStmt(s, env);
        if (last == .return_value) {
            return last;
        }
    }
    return last;
}

pub fn conditional(i: *ast.IfStmt, env: *Environment) !Value {
    const cond = try evalExpr(i.condition, env);
    if (cond != .boolean) {
        return error.TypeMismatch;
    }

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
    if (iterable != .array) {
        return error.TypeMismatch;
    }

    for (iterable.array.items, 0..) |item, i| {
        var child_env = Environment.init(env.allocator, env);
        try child_env.define(f.value, item);
        if (f.index) {
            try child_env.define(f.index_name.?, .{
                .number = @floatFromInt(i),
            });
        }

        for (f.body.items) |parsed| {
            const val = try evalStmt(parsed, &child_env);
            switch (val) {
                .break_signal => return .nil,
                .continue_signal => break,
                .return_value => |rval| return rval.*,
                else => {},
            }
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
            const val = try evalStmt(stmt, env);
            switch (val) {
                .break_signal => return .nil,
                .continue_signal => break,
                .return_value => |rval| return rval.*,
                else => {},
            }
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

    const cls_val: Value = .{
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

    const func_val: Value = .{
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
            try env.defineConstant(i.name, module_value);
            return .nil;
        }
    }

    const path = i.from;
    const writer = eval.getWriterErr();

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try writer.print("Error Opening Import: {s} from {s}\n", .{ i.name, i.from });
        try writer.print("{!}\n", .{err});
        return err;
    };
    defer file.close();

    // Parse the file using our parser, 10 MB max file size
    const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);

    const parser = @import("../parser/parser.zig");
    const parse = parser.parse;

    const ast_block = try parse(allocator, contents);

    // Tracks seen identifiers to check for invalid import requests
    var decl_names = std.StringHashMap(void).init(allocator);
    defer decl_names.deinit();
    var recursive_flag = false; // Errors should be recursively bubbled up as decl_names is not shared between scopes

    // For now, functions, variables, classes, and recursive imports will be included
    for (ast_block.block.body.items) |stmt| {
        switch (stmt.*) {
            .var_decl => |*var_decl| {
                const decl_name = var_decl.identifier;
                try decl_names.put(decl_name, {});
                if (std.mem.eql(u8, i.name, "*") or std.mem.eql(u8, i.name, decl_name)) {
                    _ = try variable(var_decl, env);
                    try env.makeConstant(decl_name); // Defines the variable in the env
                }

                // End the loop early if the requested identifier was found
                if (std.mem.eql(u8, i.name, decl_name)) {
                    break;
                }
            },
            .function_decl => |*func_decl| {
                const decl_name = func_decl.name;
                try decl_names.put(decl_name, {});
                if (std.mem.eql(u8, i.name, "*") or std.mem.eql(u8, i.name, decl_name)) {
                    _ = try function(func_decl, env); // Defines the function in the env
                    try env.makeConstant(decl_name);
                }

                // End the loop early if the requested identifier was found
                if (std.mem.eql(u8, i.name, decl_name)) {
                    break;
                }
            },
            .class_decl => |*class_decl| {
                const decl_name = class_decl.name;
                try decl_names.put(decl_name, {});
                if (std.mem.eql(u8, i.name, "*") or std.mem.eql(u8, i.name, decl_name)) {
                    _ = try class(class_decl, env); // Defines the class in the env
                    try env.makeConstant(decl_name);
                }

                // End the loop early if the requested identifier was found
                if (std.mem.eql(u8, i.name, decl_name)) {
                    break;
                }
            },
            .import_stmt => |*import_stmt| {
                const decl_name = import_stmt.name;
                try decl_names.put(decl_name, {});
                recursive_flag = true;
                _ = try import(import_stmt, env); // Defines the import in the env
                if (!std.mem.eql(u8, decl_name, "*")) {
                    try env.makeConstant(decl_name);
                }
            },
            else => {},
        }
    }

    if (!recursive_flag and !std.mem.eql(u8, i.name, "*") and !decl_names.contains(i.name)) {
        try writer.print("Identifier \"{s}\" is undefined in the requested input file.\n", .{i.name});
        return error.UndefinedIdentifier;
    }

    return .nil;
}

pub fn returns(r: *ast.ReturnStmt, env: *Environment) !Value {
    const value: Value = if (r.value) |v|
        try evalExpr(v, env)
    else
        .nil;
    const value_ptr = try env.allocator.create(Value);
    value_ptr.* = value;
    return .{
        .return_value = value_ptr,
    };
}

pub fn match(m: *ast.Match, env: *Environment) !Value {
    const match_val = try evalExpr(m.expression, env);

    for (m.cases.items) |case| {
        // Use '_' for wildcard (else)
        if (case.pattern.* == .symbol and std.mem.eql(u8, case.pattern.symbol.value, "_")) {
            return try evalStmt(case.body, env);
        }

        const pattern_val = try evalExpr(case.pattern, env);

        if (match_val.eql(pattern_val)) {
            return try evalStmt(case.body, env);
        }
    }

    return .nil;
}
