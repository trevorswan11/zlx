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
                    .string => Value{ .string = try std.fmt.allocPrint(op.allocator, "{s}{s}", .{ l, rhs.string }) },
                    else => error.TypeMismatch,
                },
                else => error.TypeMismatch,
            };
        },
        .STAR => {
            return Value{
                .number = lhs.number * rhs.number,
            };
        },
        else => return error.UnknownOperator,
    }
}

pub fn evalExpr(expr: *ast.Expr, env: *Environment) !Value {
    switch (expr.*) {
        .number => |n| return Value{ .number = n.value },
        .string => |s| return Value{ .string = s.value },
        .symbol => |s| return try env.get(s.value),
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
        .binary => |b| {
            const left = try evalExpr(b.left, env);
            const right = try evalExpr(b.right, env);
            return evalBinary(b.operator, left, right);
        },
        .assignment => |a| {
            const value = try evalExpr(a.assigned_value, env);

            switch (a.assignee.*) {
                .symbol => |s| {
                    try env.assign(s.value, value);
                    return value;
                },
                else => return error.InvalidAssignmentTarget,
            }
        },
        else => return error.UnimplementedExpr,
    }
}

pub fn evalStmt(stmt: *ast.Stmt, env: *Environment) !Value {
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
                try env.define(f.value, item);
                if (f.index) {
                    try env.define("index", Value{ .number = @floatFromInt(i) });
                }

                for (f.body.items) |parsed| {
                    const result = try evalStmt(parsed, env);
                    std.debug.print("=> {s}\n", .{result.toString(env.allocator)});
                }
            }

            return Value.nil;
        },
        else => return error.UnimplementedStmt,
    }
}
