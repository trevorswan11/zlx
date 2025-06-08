const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("interpreter.zig");
const builtins = @import("../builtins/builtins.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const evalBinary = @import("eval.zig").evalBinary;
const evalExpr = @import("eval.zig").evalExpr;
const evalStmt = @import("eval.zig").evalStmt;

pub fn number(n: *ast.NumberExpr, _: *Environment) !Value {
    return .{
        .number = n.value,
    };
}

pub fn string(s: *ast.StringExpr, _: *Environment) !Value {
    return .{
        .string = s.value,
    };
}

pub fn boolean(b: bool, _: *Environment) !Value {
    return .{
        .boolean = b,
    };
}

pub fn symbol(s: *ast.SymbolExpr, env: *Environment) !Value {
    return try env.get(s.value);
}

pub fn array(a: *ast.ArrayLiteral, env: *Environment) !Value {
    var arr = std.ArrayList(Value).init(env.allocator);
    for (a.contents.items) |item_expr| {
        const item = try evalExpr(item_expr, env);
        try arr.append(item);
    }
    return .{
        .array = arr,
    };
}

pub fn binary(b: *ast.BinaryExpr, env: *Environment) !Value {
    const left = try evalExpr(b.left, env);
    const right = try evalExpr(b.right, env);
    return evalBinary(b.operator, left, right);
}

pub fn assignment(a: *ast.AssignmentExpr, env: *Environment) !Value {
    const value = try evalExpr(a.assigned_value, env);

    switch (a.assignee.*) {
        .symbol => |s| {
            try env.assign(s.value, value);
            return value;
        },
        .member => |m| {
            var obj_val = try evalExpr(m.member, env);
            if (obj_val == .reference) {
                const ptr = obj_val.reference;
                if (ptr.* != .object) {
                    return error.TypeMismatch;
                }
                try ptr.object.put(m.property, value);
            } else if (obj_val == .object) {
                try obj_val.object.put(m.property, value);
            } else {
                return error.TypeMismatch;
            }
            return value;
        },
        .computed => |c| {
            var obj_val = try evalExpr(c.member, env);
            obj_val = obj_val.deref();
            const key_val = try evalExpr(c.property, env);

            if (obj_val != .object or key_val != .string) {
                return error.TypeMismatch;
            }

            try obj_val.object.put(key_val.string, value);
            return value;
        },
        else => return error.InvalidAssignmentTarget,
    }
}

pub fn range(r: *ast.RangeExpr, env: *Environment) !Value {
    const lower = try evalExpr(r.lower, env);
    const upper = try evalExpr(r.upper, env);

    if (lower != .number or upper != .number) {
        return error.TypeMismatch;
    }

    var arr = std.ArrayList(Value).init(env.allocator);
    var i = lower.number;
    while (i < upper.number) : (i += 1) {
        try arr.append(.{
            .number = i,
        });
    }

    return .{
        .array = arr,
    };
}

pub fn call(c: *ast.CallExpr, env: *Environment) !Value {
    if (c.method.* == .symbol) {
        const fn_name = c.method.symbol.value;

        inline for (builtins.builtin_fns) |builtin| {
            if (std.mem.eql(u8, fn_name, builtin.name)) {
                return try builtin.handler(env.allocator, c.arguments.items, env);
            }
        }
    }

    const callee_val = try evalExpr(c.method, env);
    switch (callee_val) {
        .builtin => |handler| {
            return try handler(env.allocator, c.arguments.items, env);
        },
        .function => |func| {
            if (func.parameters.len != c.arguments.items.len) {
                return error.ArityMismatch;
            }

            var call_env = Environment.init(env.allocator, func.closure);
            for (func.parameters, 0..) |param, i| {
                const arg_val = try evalExpr(c.arguments.items[i], env);
                try call_env.define(param, arg_val);
            }

            var result: Value = .nil;
            for (func.body.items) |stmt| {
                result = try evalStmt(stmt, &call_env);
                if (result == .return_value) {
                    return result.return_value.*;
                }
            }

            return result;
        },
        .bound_method => |bm| {
            const fn_decl = bm.method.function_decl;

            if (fn_decl.parameters.items.len != c.arguments.items.len) {
                return error.ArityMismatch;
            }

            var method_env = Environment.init(env.allocator, null);
            try method_env.define("this", .{
                .reference = try env.allocator.create(Value),
            });
            try method_env.assign("this", bm.instance.*);

            for (fn_decl.parameters.items, 0..) |param, i| {
                const arg_val = try evalExpr(c.arguments.items[i], env);
                try method_env.define(param.name, arg_val);
            }

            var result: Value = .nil;
            for (fn_decl.body.items) |stmt| {
                result = try evalStmt(stmt, &method_env);
            }

            return result;
        },
        else => return error.InvalidCallTarget,
    }
}

pub fn prefix(p: *ast.PrefixExpr, env: *Environment) !Value {
    if (p.operator.kind == .PLUS_PLUS or p.operator.kind == .MINUS_MINUS) {
        if (p.right.* != .symbol) {
            return error.InvalidPrefixTarget;
        }

        const name = p.right.symbol.value;
        var val = try env.get(name);

        if (val != .number) {
            return error.UnsupportedPrefixOperand;
        }

        if (p.operator.kind == .PLUS_PLUS) {
            val.number += 1;
        } else if (p.operator.kind == .MINUS_MINUS) {
            val.number -= 1;
        }

        try env.assign(name, val);
        return val;
    }

    const right = try evalExpr(p.right, env);
    return switch (p.operator.kind) {
        .MINUS => .{
            .number = -right.number,
        },
        .NOT => .{
            .boolean = !right.boolean,
        },
        .TYPEOF => .{ .string = blk: switch (right) {
            .typed_val => |t| {
                break :blk t.type;
            },
            else => "any",
        } },
        else => error.UnsupportedPrefixOperator,
    };
}

pub fn member(m: *ast.MemberExpr, env: *Environment) !Value {
    var target = try evalExpr(m.member, env);
    target = target.deref();

    if (target != .object) {
        return error.TypeMismatch;
    }

    const map = &target.object;

    if (map.get(m.property)) |val| {
        return val;
    } else if (map.get("__class_name")) |cls_name_val| {
        if (cls_name_val != .string) {
            return error.InvalidClassRef;
        }

        const class_val = try env.get(cls_name_val.string);
        if (class_val != .class) {
            return error.InvalidClassRef;
        }

        if (class_val.class.methods.get(m.property)) |method_stmt| {
            const val = try env.allocator.create(Value);
            val.* = target;
            return .{
                .bound_method = .{
                    .instance = val,
                    .method = method_stmt,
                },
            };
        }
    }
    return error.PropertyNotFound;
}

pub fn computed(c: *ast.ComputedExpr, env: *Environment) !Value {
    var target = try evalExpr(c.member, env);
    target = target.deref();
    const key = try evalExpr(c.property, env);

    switch (target) {
        .array => |arr| {
            if (key != .number) {
                return error.TypeMismatch;
            }
            const index: usize = @intFromFloat(key.number);
            if (index >= arr.items.len) {
                return error.IndexOutOfBounds;
            }
            return arr.items[index];
        },
        .object => |map| {
            if (key != .string) {
                return error.TypeMismatch;
            }
            if (map.get(key.string)) |val| {
                return val;
            } else {
                return error.PropertyNotFound;
            }
        },
        else => return error.InvalidAccess,
    }
}

pub fn function(f: *ast.FunctionExpr, env: *Environment) !Value {
    const param_names = try env.allocator.alloc([]const u8, f.parameters.items.len);
    for (f.parameters.items, 0..) |p, i| {
        param_names[i] = p.name;
    }

    return .{
        .function = .{
            .body = f.body,
            .parameters = param_names,
            .closure = env,
        },
    };
}

pub fn new(n: *ast.NewExpr, env: *Environment) !Value {
    const class_val = try evalExpr(n.instantiation.method, env);
    if (class_val != .class) {
        return error.TypeMismatch;
    }

    const cls = class_val.class;

    const instance_ptr = try env.allocator.create(Value);
    instance_ptr.* = Value{
        .object = std.StringHashMap(Value).init(env.allocator),
    };
    try instance_ptr.*.object.put("__class_name", .{
        .string = cls.name,
    });

    if (cls.constructor) |ctor_stmt| {
        const args = n.instantiation.arguments.items;

        var ctor_env = Environment.init(env.allocator, null);
        defer ctor_env.deinit();

        try ctor_env.define("this", .{
            .reference = instance_ptr,
        });

        const fn_decl = ctor_stmt.function_decl;
        if (args.len != fn_decl.parameters.items.len) {
            return error.InvalidConstructor;
        }

        for (args, fn_decl.parameters.items) |arg_expr, param| {
            const val = try evalExpr(arg_expr, env);
            try ctor_env.define(param.name, val);
        }

        for (fn_decl.body.items) |stmt| {
            _ = try evalStmt(stmt, &ctor_env);
        }
    }

    return instance_ptr.*;
}

pub fn object(o: *ast.ObjectExpr, env: *Environment) !Value {
    var map = std.StringHashMap(Value).init(env.allocator);

    for (o.entries.items) |entry| {
        const val = try evalExpr(entry.value, env);
        try map.put(entry.key, val);
    }

    return .{
        .object = map,
    };
}

pub fn match(m: *ast.Match, env: *Environment) !Value {
    const target = try evalExpr(m.expression, env);

    for (m.cases.items) |case| {
        if (case.pattern.* == .symbol and std.mem.eql(u8, case.pattern.symbol.value, "_")) {
            return try evalExpr(case.body.expression.expression, env);
        }

        const pattern_val = try evalExpr(case.pattern, env);
        if (target.eql(pattern_val)) {
            return try evalExpr(case.body.expression.expression, env);
        }
    }

    return .nil;
}
