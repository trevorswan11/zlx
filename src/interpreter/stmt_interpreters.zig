const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("interpreter.zig");
const builtins = @import("../builtins/builtins.zig");
const eval = @import("eval.zig");
const driver = @import("../utils/driver.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const evalBinary = eval.evalBinary;
const evalExpr = eval.evalExpr;
const evalStmt = eval.evalStmt;
const getStdStructName = builtins.getStdStructName;

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
                        ._type = s.value_type,
                    },
                };
                if (v.constant) {
                    try env.declareConstant(v.identifier, to_put);
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
                        ._type = type_str,
                    },
                };
                if (v.constant) {
                    try env.declareConstant(v.identifier, to_put);
                } else {
                    try env.define(v.identifier, to_put);
                }
                return .nil;
            },
        }
    }
    if (v.constant) {
        try env.declareConstant(v.identifier, val);
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
    const writer_err = driver.getWriterErr();
    if (cond != .boolean) {
        try writer_err.print("Conditional statement requires a boolean condition, got {s}\n", .{@tagName(cond)});
        return error.TypeMismatch;
    }

    var child_arena = std.heap.ArenaAllocator.init(env.allocator);
    defer child_arena.deinit();
    const child_allocator = child_arena.allocator();

    var child_env = Environment.init(child_allocator, env);
    defer child_env.deinit();

    if (cond.boolean) {
        return try evalStmt(i.consequent, env);
    } else if (i.alternate) |alt| {
        return try evalStmt(alt, env);
    } else {
        return .nil;
    }
}

pub fn foreach(f: *ast.ForeachStmt, env: *Environment) !Value {
    var iterable = try evalExpr(f.iterable, env);
    const writer_err = driver.getWriterErr();

    if (iterable == .std_instance) {
        const instance = iterable.std_instance;
        if (instance._type.std_struct.methods.get("items")) |items_fn| {
            var mut_instance = iterable;
            const result = try items_fn(&mut_instance, &[_]*ast.Expr{}, env);
            if (result != .array) {
                try writer_err.print("std_instance.items() must return an array, got a(n) {s}\n", .{@tagName(result)});
                return error.TypeMismatch;
            }
            iterable = result;
        } else {
            try writer_err.print("Standard library type {s} does not implement items()\n", .{try getStdStructName(&iterable)});
            return error.TypeMismatch;
        }
    } else if (iterable != .array) {
        try writer_err.print("Can only iterate over array values, got {s}\n", .{@tagName(iterable)});
        return error.TypeMismatch;
    }
    iterable = iterable.deref();

    // Watch out for this 
    var child_arena = std.heap.ArenaAllocator.init(env.allocator);
    defer child_arena.deinit();
    const child_allocator = child_arena.allocator();

    for (iterable.array.items, 0..) |item, i| {
        var child_env = Environment.init(child_allocator, env);
        defer child_env.deinit();

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
    const writer_err = driver.getWriterErr();
    while (true) {
        const cond = try evalExpr(w.condition, env);
        if (cond != .boolean) {
            try writer_err.print("While loop requires a boolean condition, got {s}\n", .{@tagName(cond)});
            return error.TypeMismatch;
        }
        if (!cond.boolean) {
            break;
        }

        // Watch out for this 
        var child_arena = std.heap.ArenaAllocator.init(env.allocator);
        defer child_arena.deinit();
        const child_allocator = child_arena.allocator();

        var child_env = Environment.init(child_allocator, env);
        defer child_env.deinit();

        for (w.body.items) |stmt| {
            const val = try evalStmt(stmt, &child_env);
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

pub fn structure(c: *ast.StructDeclarationStmt, env: *Environment) !Value {
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
        .structure = .{
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
            try env.declareConstant(i.name, module_value);
            return .nil;
        }
    }

    const path = i.from;
    const writer_err = driver.getWriterErr();

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try writer_err.print("Error Opening Import: {s} from {s}\n", .{ i.name, i.from });
        try writer_err.print("{!}\n", .{err});
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

    // For now, functions, variables, structs, and recursive imports will be included
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
            .struct_decl => |*struct_decl| {
                const decl_name = struct_decl.name;
                try decl_names.put(decl_name, {});
                if (std.mem.eql(u8, i.name, "*") or std.mem.eql(u8, i.name, decl_name)) {
                    _ = try structure(struct_decl, env); // Defines the struct in the env
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
        try writer_err.print("Identifier \"{s}\" is undefined in the requested input file.\n", .{i.name});
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
    var child_env = Environment.init(env.allocator, env);
    defer child_env.deinit();
    const match_val = try evalExpr(m.expression, &child_env);

    for (m.cases.items) |case| {
        // Use '_' for wildcard (else)
        if (case.pattern.* == .symbol and std.mem.eql(u8, case.pattern.symbol.value, "_")) {
            return try evalStmt(case.body, &child_env);
        }

        const pattern_val = try evalExpr(case.pattern, &child_env);

        if (match_val.eql(pattern_val)) {
            return try evalStmt(case.body, &child_env);
        }
    }

    return .nil;
}

pub fn enumerate(e: *ast.EnumDeclarationStmt, env: *Environment) !Value {
    var enum_obj = std.StringHashMap(Value).init(env.allocator);

    for (e.variants, 0..) |variant, i| {
        try enum_obj.put(variant, .{
            .number = @floatFromInt(i),
        });
    }

    try env.define(e.name, .{
        .object = enum_obj,
    });
    return .nil;
}
