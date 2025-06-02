const std = @import("std");

const ast = @import("../ast/ast.zig");
const environment = @import("environment.zig");
const tokens = @import("../lexer/token.zig");
const builtins = @import("builtins.zig");

const Token = tokens.Token;
const Environment = environment.Environment;
const Value = environment.Value;

fn evalBinary(op: Token, lhs: Value, rhs: Value) !Value {
    switch (op.kind) {
        .PLUS => {
            return switch (lhs) {
                .number => |l| switch (rhs) {
                    .number => Value{
                        .number = l + rhs.number,
                    },
                    else => error.TypeMismatch,
                },
                .string => |l| switch (rhs) {
                    .string => Value{
                        .string = try std.fmt.allocPrint(op.allocator, "{s}{s}", .{ l, rhs.string }),
                    },
                    else => error.TypeMismatch,
                },
                else => error.TypeMismatch,
            };
        },
        .MINUS => {
            return switch (lhs) {
                .number => |l| switch (rhs) {
                    .number => Value{
                        .number = l - rhs.number,
                    },
                    else => error.TypeMismatch,
                },
                else => error.TypeMismatch,
            };
        },
        .STAR => {
            return switch (lhs) {
                .number => |l| switch (rhs) {
                    .number => Value{
                        .number = l * rhs.number,
                    },
                    else => error.TypeMismatch,
                },
                else => error.TypeMismatch,
            };
        },
        .SLASH => {
            return switch (lhs) {
                .number => |l| switch (rhs) {
                    .number => Value{
                        .number = l / rhs.number,
                    },
                    else => error.TypeMismatch,
                },
                else => error.TypeMismatch,
            };
        },
        else => return error.UnknownOperator,
    }
}

pub fn evalExpr(expr: *ast.Expr, env: *Environment) anyerror!Value {
    switch (expr.*) {
        .number => |*n| return Value{ .number = n.value },
        .string => |*s| return Value{ .string = s.value },
        .symbol => |*s| return try env.get(s.value),
        .array_literal => |a| {
            var array = std.ArrayList(Value).init(env.allocator);
            for (a.contents.items) |item_expr| {
                const item = try evalExpr(item_expr, env);
                try array.append(item);
            }
            return Value{
                .array = array,
            };
        },
        .binary => |*b| {
            const left = try evalExpr(b.left, env);
            const right = try evalExpr(b.right, env);
            return evalBinary(b.operator, left, right);
        },
        .assignment => |*a| {
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
        },
        .range_expr => |*r| {
            const lower = try evalExpr(r.lower, env);
            const upper = try evalExpr(r.upper, env);

            if (lower != .number or upper != .number) {
                return error.TypeMismatch;
            }

            var array = std.ArrayList(Value).init(env.allocator);
            var i = lower.number;
            while (i < upper.number) : (i += 1) {
                try array.append(Value{
                    .number = i,
                });
            }

            return Value{
                .array = array,
            };
        },
        .call => |*c| {
            if (c.method.* == .symbol) {
                const fn_name = c.method.symbol.value;

                inline for (builtins.builtin_fns) |builtin| {
                    if (std.mem.eql(u8, fn_name, builtin.name)) {
                        return try builtin.handler(env.allocator, c.arguments.items, env);
                    }
                }
            }

            const stderr = std.io.getStdErr().writer();
            const callee = evalExpr(c.method, env) catch |err| {
                try stderr.print("Error evaluating call target: {any}\n", .{err});
                return err;
            };

            switch (callee) {
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
                        result = evalStmt(stmt, &call_env) catch return Value.nil;
                    }

                    return result;
                },
                else => return error.InvalidCallTarget,
            }
        },
        .prefix => |*p| {
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
                .MINUS => Value{
                    .number = -right.number,
                },
                .NOT => Value{
                    .boolean = !right.boolean,
                },
                else => error.UnsupportedPrefixOperator,
            };
        },
        .member => |*m| {
            var target = try evalExpr(m.member, env);
            target = target.deref();

            if (target != .object) {
                return error.TypeMismatch;
            }

            const map = &target.object;

            if (map.get(m.property)) |val| {
                return val;
            } else {
                return error.PropertyNotFound;
            }
        },
        .computed => |*c| {
            var target = try evalExpr(c.member, env);
            target = target.deref();
            const key = try evalExpr(c.property, env);

            switch (target) {
                .array => |arr| {
                    if (key != .number) {
                        return error.TypeMismatch;
                    }
                    const index: usize = @intFromFloat(key.number);
                    if (index >= arr.items.len) return error.IndexOutOfBounds;
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
        },
        .function_expr => |*f| {
            const param_names = try env.allocator.alloc([]const u8, f.parameters.items.len);
            for (f.parameters.items, 0..) |p, i| {
                param_names[i] = p.name;
            }

            return Value{
                .function = .{
                    .body = f.body,
                    .parameters = param_names,
                    .closure = env,
                },
            };
        },
        .new_expr => |*n| {
            const class_val = try evalExpr(n.instantiation.method, env);
            if (class_val != .class) {
                return error.TypeMismatch;
            }

            const cls = class_val.class;

            const instance_ptr = try env.allocator.create(Value);
            instance_ptr.* = Value{
                .object = std.StringHashMap(Value).init(env.allocator),
            };

            if (cls.constructor) |ctor_stmt| {
                const args = n.instantiation.arguments.items;

                var ctor_env = Environment.init(env.allocator, null);
                defer ctor_env.deinit();

                try ctor_env.define("this", Value{
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
        },
        .object => |*o| {
            var map = std.StringHashMap(Value).init(env.allocator);

            for (o.entries.items) |entry| {
                const val = try evalExpr(entry.value, env);
                try map.put(entry.key, val);
            }

            return Value{
                .object = map,
            };
        },
    }
}

pub fn evalStmt(stmt: *ast.Stmt, env: *Environment) anyerror!Value {
    switch (stmt.*) {
        .var_decl => |*v| {
            const val = if (v.assigned_value) |a| try evalExpr(a, env) else Value.nil;
            try env.define(v.identifier, val);
            return Value.nil;
        },
        .expression => |*e| {
            return try evalExpr(e.expression, env);
        },
        .block => |*b| {
            var last: Value = .nil;
            for (b.body.items) |s| {
                last = try evalStmt(s, env);
            }
            return last;
        },
        .if_stmt => |*i| {
            const cond = try evalExpr(i.condition, env);
            if (cond != Value.boolean) return error.TypeMismatch;

            if (cond.boolean) {
                return try evalStmt(i.consequent, env);
            } else if (i.alternate) |alt| {
                return try evalStmt(alt, env);
            } else {
                return Value.nil;
            }
        },
        .foreach_stmt => |*f| {
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

            return Value.nil;
        },
        .class_decl => |*c| {
            var constructor: ?*ast.Stmt = null;

            for (c.body.items) |statement| {
                if (statement.* == .function_decl) {
                    const fn_decl = statement.function_decl;
                    if (std.mem.eql(u8, fn_decl.name, "constructor")) {
                        constructor = statement;
                        break;
                    }
                }
            }

            const cls_val = Value{
                .class = .{
                    .name = c.name,
                    .body = c.body,
                    .constructor = constructor,
                },
            };
            try env.define(c.name, cls_val);
            return Value.nil;
        },
        .function_decl => |*f| {
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
            return Value.nil;
        },
        .import_stmt => |*i| {
            const allocator = env.allocator;
            for (builtins.builtin_modules) |builtin| {
                if (std.mem.eql(u8, builtin.name, i.from)) {
                    const module_value = try builtin.loader(allocator);
                    try env.assign(i.name, module_value);
                    return Value.nil;
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
        },
    }
}
