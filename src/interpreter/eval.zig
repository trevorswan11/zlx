const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("interpreter.zig");
const token = @import("../lexer/token.zig");
const builtins = @import("../builtins/builtins.zig");
const expr_interpreters = @import("expr_interpreters.zig");
const stmt_interpreters = @import("stmt_interpreters.zig");
const binary_interpreters = @import("binary_interpreters.zig");
const driver = @import("../utils/driver.zig");

const Token = token.Token;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn evalBinary(op: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (op.kind) {
        .PLUS => return try binary_interpreters.plus(op, lhs, rhs),
        .MINUS => return try binary_interpreters.minus(op, lhs, rhs),
        .STAR => return try binary_interpreters.star(op, lhs, rhs),
        .SLASH => return try binary_interpreters.slash(op, lhs, rhs),
        .EQUALS => return try binary_interpreters.equal(op, lhs, rhs),
        .NOT_EQUALS => return try binary_interpreters.notEqual(op, lhs, rhs),
        .GREATER => return try binary_interpreters.greater(op, lhs, rhs),
        .GREATER_EQUALS => return try binary_interpreters.greaterEqual(op, lhs, rhs),
        .LESS => return try binary_interpreters.less(op, lhs, rhs),
        .LESS_EQUALS => return try binary_interpreters.lessEqual(op, lhs, rhs),
        .PERCENT => return try binary_interpreters.mod(op, lhs, rhs),
        .AND => return try binary_interpreters.boolAnd(op, lhs, rhs),
        .OR => return try binary_interpreters.boolOr(op, lhs, rhs),
        .BITWISE_AND => return try binary_interpreters.bitwiseAnd(op, lhs, rhs),
        .BITWISE_OR => return try binary_interpreters.bitwiseOr(op, lhs, rhs),
        .BITWISE_XOR => return try binary_interpreters.bitwiseXor(op, lhs, rhs),
        else => {
            try writer_err.print("Operator {s} is not a valid binary operator\n", .{@tagName(op.kind)});
            return error.UnknownBinaryOperator;
        },
    }
}

pub fn evalExpr(expr: *ast.Expr, env: *Environment) anyerror!Value {
    switch (expr.*) {
        .number => |*n| return try expr_interpreters.number(n, env),
        .string => |*s| return try expr_interpreters.string(s, env),
        .boolean => |b| return expr_interpreters.boolean(b, env),
        .symbol => |*s| return try expr_interpreters.symbol(s, env),
        .array_literal => |*a| return try expr_interpreters.array(a, env),
        .binary => |*b| return try expr_interpreters.binary(b, env),
        .assignment => |*a| return try expr_interpreters.assignment(a, env),
        .range_expr => |*r| return try expr_interpreters.range(r, env),
        .call => |*c| return try expr_interpreters.call(c, env),
        .prefix => |*p| return try expr_interpreters.prefix(p, env),
        .postfix => |*p| return try expr_interpreters.postfix(p, env),
        .member => |*m| return expr_interpreters.member(m, env),
        .computed => |*c| return try expr_interpreters.computed(c, env),
        .function_expr => |*f| return try expr_interpreters.function(f, env),
        .new_expr => |*n| return try expr_interpreters.new(n, env),
        .object => |*o| return try expr_interpreters.object(o, env),
        .match_expr => |*m| return try expr_interpreters.match(m, env),
        .compound_assignment => |*c| return try expr_interpreters.compoundAssignment(c, env),
        .nil => |n| return try expr_interpreters.nil(n, env),
    }
}

pub fn evalStmt(stmt: *ast.Stmt, env: *Environment) anyerror!Value {
    switch (stmt.*) {
        .var_decl => |*v| return try stmt_interpreters.variable(v, env),
        .expression => |*e| return try stmt_interpreters.expression(e, env),
        .block => |*b| return try stmt_interpreters.block(b, env),
        .if_stmt => |*i| return try stmt_interpreters.conditional(i, env),
        .foreach_stmt => |*f| return try stmt_interpreters.foreach(f, env),
        .while_stmt => |*w| return try stmt_interpreters.while_loop(w, env),
        .struct_decl => |*c| return try stmt_interpreters.structure(c, env),
        .function_decl => |*f| return try stmt_interpreters.function(f, env),
        .import_stmt => |*i| return try stmt_interpreters.import(i, env),
        .break_stmt => |_| return .break_signal,
        .continue_stmt => |_| return .continue_signal,
        .return_stmt => |*s| return try stmt_interpreters.returns(s, env),
        .match_stmt => |*m| return try stmt_interpreters.match(m, env),
    }
}
