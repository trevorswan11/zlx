const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("interpreter.zig");
const builtins = @import("../builtins/builtins.zig");
const eval = @import("eval.zig");
const token = @import("../lexer/token.zig");
const driver = @import("../utils/driver.zig");

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const evalBinary = eval.evalBinary;
const evalExpr = eval.evalExpr;
const evalStmt = eval.evalStmt;

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
    const writer_err = driver.getWriterErr();

    switch (a.assignee.*) {
        .symbol => |s| {
            try env.assign(s.value, value);
            return value;
        },
        .member => |m| {
            var obj_val = try evalExpr(m.member, env);
            if (obj_val == .reference) {
                obj_val = obj_val.deref();
                if (obj_val != .object) {
                    try writer_err.print("Expected assignee to be an object but found {s}\n", .{@tagName(obj_val)});
                    return error.TypeMismatch;
                }
                try obj_val.object.put(m.property, value);
            } else if (obj_val == .object) {
                try obj_val.object.put(m.property, value);
            } else {
                try writer_err.print("Expected assignee to be an object or reference to an object but found {s}\n", .{@tagName(obj_val)});
                return error.TypeMismatch;
            }
            return value;
        },
        .computed => |c| {
            var obj_val = try evalExpr(c.member, env);
            obj_val = obj_val.deref();
            const key_val = try evalExpr(c.property, env);

            if (obj_val != .object or key_val != .string) {
                try writer_err.print("Computed expressions require an object value and string key but found pair: ({s}, {s})\n", .{ @tagName(obj_val), @tagName(key_val) });
                return error.InvalidComputeTarget;
            }

            try obj_val.object.put(key_val.string, value);
            return value;
        },
        else => {
            try writer_err.print("Assignment expressions work only on symbol, member and computed exprs; found {s}\n", .{@tagName(a.assignee.*)});
            return error.InvalidAssignmentTarget;
        },
    }
}

pub fn range(r: *ast.RangeExpr, env: *Environment) !Value {
    const lower = try evalExpr(r.lower, env);
    const upper = try evalExpr(r.upper, env);

    const writer_err = driver.getWriterErr();
    if (lower != .number or upper != .number) {
        try writer_err.print("Cannot make range between types {s} and {s}; Two numbers are required\n", .{ @tagName(lower), @tagName(upper) });
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
    const writer_err = driver.getWriterErr();
    switch (callee_val) {
        .builtin => |handler| {
            return try handler(env.allocator, c.arguments.items, env);
        },
        .function => |func| {
            if (func.parameters.len != c.arguments.items.len) {
                try writer_err.print("Function expected {d} parameters, but {d} were given\n", .{ func.parameters.len, c.arguments.items.len });
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
                try writer_err.print("Function expected {d} parameters, but {d} were given\n", .{ fn_decl.parameters.items.len, c.arguments.items.len });
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
        .bound_std_method => {
            const bound = callee_val.bound_std_method;
            return try bound.method(env.allocator, bound.instance, c.arguments.items, env);
        },
        else => {
            try writer_err.print("Cannot invoke call on type {s}\n", .{@tagName(callee_val)});
            return error.InvalidCallTarget;
        },
    }
}

pub fn prefix(p: *ast.PrefixExpr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (p.operator.kind == .PLUS_PLUS or p.operator.kind == .MINUS_MINUS) {
        if (p.right.* != .symbol) {
            try writer_err.print("Cannot invoke '++' or '--' prefix operator on type {s}\n", .{@tagName(p.right.*)});
            return error.InvalidPrefixTarget;
        }

        const name = p.right.symbol.value;
        var val = try env.get(name);

        if (val != .number) {
            try writer_err.print("Cannot invoke '++' or '--' prefix operator on a non-number, got {s}\n", .{@tagName(p.right.*)});
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
    switch (p.operator.kind) {
        .MINUS => return .{
            .number = -right.number,
        },
        .NOT => return .{
            .boolean = !right.boolean,
        },
        .TYPEOF => return .{
            .string = blk: switch (right) {
                .typed_val => |t| {
                    break :blk t.type;
                },
                else => "any",
            },
        },
        .DELETE => {
            if (p.right.* == .symbol) {
                return env.remove(p.right.symbol.value);
            } else {
                try writer_err.print("Can only delete symbol expressions, got a(n) {s}\n", .{@tagName(p.right.*)});
                return error.TypeMismatch;
            }
        },
        else => {
            const operator_kind_str = try token.tokenKindString(env.allocator, p.operator.kind);
            defer env.allocator.free(operator_kind_str);
            try writer_err.print("Operator {s} is not a valid prefix operator\n", .{operator_kind_str});
            return error.UnsupportedPrefixOperator;
        },
    }
}

pub fn postfix(p: *ast.PostfixExpr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    if (p.operator.kind == .PLUS_PLUS or p.operator.kind == .MINUS_MINUS) {
        if (p.left.* != .symbol) {
            try writer_err.print("Cannot invoke postfix '++' or '--' on type {s}\n", .{@tagName(p.left.*)});
            return error.InvalidPostfixTarget;
        }

        const name = p.left.symbol.value;
        var val = try env.get(name);

        if (val != .number) {
            try writer_err.print("Postfix operator requires a number, got {s}\n", .{@tagName(val)});
            return error.UnsupportedPostfixOperand;
        }

        const original = val; // Postfix operators should return original before using operator

        if (p.operator.kind == .PLUS_PLUS) {
            val.number += 1;
        } else if (p.operator.kind == .MINUS_MINUS) {
            val.number -= 1;
        }

        try env.assign(name, val);
        return original;
    }

    const operator_kind_str = try token.tokenKindString(env.allocator, p.operator.kind);
    defer env.allocator.free(operator_kind_str);
    try writer_err.print("Operator {s} is not a valid postfix operator\n", .{operator_kind_str});
    return error.UnsupportedPostfixOperator;
}

pub fn member(m: *ast.MemberExpr, env: *Environment) !Value {
    var target = try evalExpr(m.member, env);
    const writer_err = driver.getWriterErr();
    target = target.deref();

    switch (target) {
        .object => |*obj| {
            if (obj.get(m.property)) |val| {
                return val;
            } else if (obj.get("__struct_name")) |cls_name_val| {
                if (cls_name_val != .string) {
                    try writer_err.print("Struct name was expected to be a string, got {s}\n", .{@tagName(cls_name_val)});
                    return error.InvalidStructRef;
                }

                const struct_val = try env.get(cls_name_val.string);
                if (struct_val != .structure) {
                    try writer_err.print("Struct name was expected to be a string, got {s}\n", .{@tagName(cls_name_val)});
                    return error.InvalidStructRef;
                }

                if (struct_val.structure.methods.get(m.property)) |method_stmt| {
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
            try writer_err.print("Could not evaluate member expression as property {s} was not found\n", .{m.property});
            return error.PropertyNotFound;
        },
        .std_instance => |inst| {
            if (inst.fields.get(m.property)) |val_ptr| {
                return val_ptr.*;
            }

            // Then try method
            if (inst._type.* != .std_struct) {
                try writer_err.print("std_instance.type is not a std_struct\n", .{});
                return error.InvalidStructRef;
            }

            const method_map = inst._type.std_struct.methods;
            if (method_map.get(m.property)) |method_fn| {
                const val = try env.allocator.create(Value);
                val.* = target;
                return .{
                    .bound_std_method = .{
                        .instance = val,
                        .method = method_fn,
                    },
                };
            }

            try writer_err.print("Property \"{s}\" not found on std_instance of {s}\n", .{ m.property, inst._type.std_struct.name });
            return error.PropertyNotFound;
        },
        .pair => |pair| {
            if (std.mem.eql(u8, "first", m.property)) {
                return pair.first.*;
            } else if (std.mem.eql(u8, "second", m.property)) {
                return pair.second.*;
            } else {
                try writer_err.print("Pair values contain only fields 'first' and 'second', found {s}\n", .{m.property});
                return error.PropertyNotFound;
            }
        },
        else => {
            try writer_err.print("Member expression expects object or std_instance, got {s}\n", .{@tagName(target)});
            return error.TypeMismatch;
        },
    }
}

pub fn computed(c: *ast.ComputedExpr, env: *Environment) !Value {
    var target = try evalExpr(c.member, env);
    const key = try evalExpr(c.property, env);
    const writer_err = driver.getWriterErr();
    target = target.deref();

    switch (target) {
        .array => |arr| {
            if (key != .number) {
                try writer_err.print("Can only perform compute expression on an array with a number key, got {s}\n", .{@tagName(key)});
                return error.TypeMismatch;
            }
            const index: usize = @intFromFloat(key.number);
            if (index >= arr.items.len) {
                try writer_err.print("Index {d} is out of bounds for array of length {d}\n", .{ index, arr.items.len });
                return error.IndexOutOfBounds;
            }
            return arr.items[index];
        },
        .object => |map| {
            if (key != .string) {
                try writer_err.print("Can only perform compute expression on an object with a string key, got {s}\n", .{@tagName(key)});
                return error.TypeMismatch;
            }
            if (map.get(key.string)) |val| {
                return val;
            } else {
                try writer_err.print("Could not evaluate compute expression as property {s} was not found\n", .{key.string});
                return error.PropertyNotFound;
            }
        },
        .pair => |pair| {
            if (key != .string) {
                try writer_err.print("Can only perform compute expression on a pair with a string key, got {s}\n", .{@tagName(key)});
                return error.TypeMismatch;
            }

            if (std.mem.eql(u8, "first", key.string)) {
                return pair.first.*;
            } else if (std.mem.eql(u8, "second", key.string)) {
                return pair.second.*;
            } else {
                try writer_err.print("Pair values contain only fields 'first' and 'second', found {s}\n", .{key.string});
                return error.PropertyNotFound;
            }
        },
        else => {
            try writer_err.print("Target type {s} does not support computed expressions\n", .{@tagName(target)});
            return error.InvalidAccess;
        },
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
    const struct_val = try evalExpr(n.instantiation.method, env);
    const writer_err = driver.getWriterErr();
    const args = n.instantiation.arguments.items;

    return switch (struct_val) {
        .structure => |cls| blk: {
            const instance_ptr = try env.allocator.create(Value);
            instance_ptr.* = .{
                .object = std.StringHashMap(Value).init(env.allocator),
            };
            try instance_ptr.*.object.put("__struct_name", .{
                .string = cls.name,
            });

            if (cls.constructor) |ctor_stmt| {
                var ctor_env = Environment.init(env.allocator, null);
                defer ctor_env.deinit();

                try ctor_env.define("this", .{
                    .reference = instance_ptr,
                });

                const fn_decl = ctor_stmt.function_decl;
                if (args.len != fn_decl.parameters.items.len) {
                    try writer_err.print("Constructor expected {d} parameters, but {d} were given\n", .{ fn_decl.parameters.items.len, args.len });
                    break :blk error.InvalidConstructorArity;
                }

                for (args, fn_decl.parameters.items) |arg_expr, param| {
                    const val = try evalExpr(arg_expr, env);
                    try ctor_env.define(param.name, val);
                }

                for (fn_decl.body.items) |stmt| {
                    _ = try evalStmt(stmt, &ctor_env);
                }
            }

            break :blk instance_ptr.*;
        },
        .std_struct => |std_struct| blk: {
            const ctor = std_struct.constructor;
            break :blk try ctor(env.allocator, args, env);
        },
        else => blk: {
            try writer_err.print("The 'new' keyword can only be used when creating a struct, got {s}\n", .{@tagName(struct_val)});
            break :blk error.TypeMismatch;
        },
    };
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

pub fn compoundAssignment(a: *ast.CompoundAssignmentExpr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const lhs_val = try evalExpr(a.assignee, env);
    const rhs_val = try evalExpr(a.value, env);

    const binary_kind: token.TokenKind = switch (a.operator.kind) {
        .PLUS_EQUALS => .PLUS,
        .MINUS_EQUALS => .MINUS,
        .STAR_EQUALS => .STAR,
        .SLASH_EQUALS => .SLASH,
        .PERCENT_EQUALS => .PERCENT,
        else => {
            try writer_err.print("Cannot perform compound assignment using token {s}\n", .{@tagName(a.operator.kind)});
            return error.InvalidCompoundOperator;
        },
    };

    const result = try eval.evalBinary(.{
        .kind = binary_kind,
        .allocator = a.operator.allocator,
        .line = a.operator.line,
        .value = a.operator.value,
        .start = a.operator.start,
        .end = a.operator.end,
    }, lhs_val, rhs_val);

    const assignment_expr = try env.allocator.create(ast.AssignmentExpr);
    switch (result) {
        .number => |num| {
            assignment_expr.* = .{
                .assignee = a.assignee,
                .assigned_value = try env.boxExpr(.{ .number = .{
                    .value = num,
                } }),
            };
        },
        .string => |str| {
            assignment_expr.* = .{
                .assignee = a.assignee,
                .assigned_value = try env.boxExpr(.{ .string = .{
                    .value = str,
                } }),
            };
        },
        else => {
            try writer_err.print("Cannot perform compound assignment on type {s}\n", .{@tagName(result)});
            return error.TypeMismatch;
        },
    }

    return try assignment(assignment_expr, env);
}

pub fn nil(_: void, _: *Environment) !Value {
    return .nil;
}
