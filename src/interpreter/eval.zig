const std = @import("std");

const ast = @import("../ast/ast.zig");
const environment = @import("environment.zig");
const tokens = @import("../lexer/token.zig");

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

                inline for (@import("call_dispatch.zig").builtins) |builtin| {
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
            _ = m;
            return error.UnimplementedExpr;
        },
        .computed => |*c| {
            _ = c;
            return error.UnimplementedExpr;
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
        .new_expr => |*e| {
            _ = e;
            return error.UnimplementedExpr;
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
                    try child_env.define("index", Value{ .number = @floatFromInt(i) });
                }

                for (f.body.items) |parsed| {
                    _ = try evalStmt(parsed, &child_env);
                }
            }

            return Value.nil;
        },
        .class_decl => |*c| {
            _ = c;
            return error.UnimplementedStmt;
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
            const path = i.from;
            const stderr = std.io.getStdErr().writer();

            const file = std.fs.cwd().openFile(path, .{}) catch |err| {
                try stderr.print("Error Opening Import: {s} from {s}\n", .{i.name, i.from});
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
