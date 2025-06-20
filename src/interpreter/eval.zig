const std = @import("std");

const ast = @import("../parser/ast.zig");
const interpreter = @import("interpreter.zig");
const token = @import("../lexer/token.zig");
const builtins = @import("../builtins/builtins.zig");
const expr_handlers = @import("expr_handlers.zig");
const stmt_handlers = @import("stmt_handlers.zig");
const binary_handlers = @import("binary_handlers.zig");
const driver = @import("../utils/driver.zig");

const Token = token.Token;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

pub fn evalBinary(op: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (op.kind) {
        .PLUS => return try binary_handlers.plus(op, lhs, rhs),
        .MINUS => return try binary_handlers.minus(op, lhs, rhs),
        .STAR => return try binary_handlers.star(op, lhs, rhs),
        .SLASH => return try binary_handlers.slash(op, lhs, rhs),
        .EQUALS => return try binary_handlers.equal(op, lhs, rhs),
        .NOT_EQUALS => return try binary_handlers.notEqual(op, lhs, rhs),
        .GREATER => return try binary_handlers.greater(op, lhs, rhs),
        .GREATER_EQUALS => return try binary_handlers.greaterEqual(op, lhs, rhs),
        .LESS => return try binary_handlers.less(op, lhs, rhs),
        .LESS_EQUALS => return try binary_handlers.lessEqual(op, lhs, rhs),
        .PERCENT => return try binary_handlers.mod(op, lhs, rhs),
        .AND => return try binary_handlers.boolAnd(op, lhs, rhs),
        .OR => return try binary_handlers.boolOr(op, lhs, rhs),
        .BITWISE_AND => return try binary_handlers.bitwiseAnd(op, lhs, rhs),
        .BITWISE_OR => return try binary_handlers.bitwiseOr(op, lhs, rhs),
        .BITWISE_XOR => return try binary_handlers.bitwiseXor(op, lhs, rhs),
        else => {
            try writer_err.print("Operator {s} is not a valid binary operator\n", .{@tagName(op.kind)});
            return error.UnknownBinaryOperator;
        },
    }
}

pub fn evalExpr(expr: *ast.Expr, env: *Environment) anyerror!Value {
    switch (expr.*) {
        .number => |*n| return try expr_handlers.number(n, env),
        .string => |*s| return try expr_handlers.string(s, env),
        .boolean => |b| return expr_handlers.boolean(b, env),
        .symbol => |*s| return try expr_handlers.symbol(s, env),
        .array_literal => |*a| return try expr_handlers.array(a, env),
        .binary => |*b| return try expr_handlers.binary(b, env),
        .assignment => |*a| return try expr_handlers.assignment(a, env),
        .range_expr => |*r| return try expr_handlers.range(r, env),
        .call => |*c| return try expr_handlers.call(c, env),
        .prefix => |*p| return try expr_handlers.prefix(p, env),
        .postfix => |*p| return try expr_handlers.postfix(p, env),
        .member => |*m| return expr_handlers.member(m, env),
        .computed => |*c| return try expr_handlers.computed(c, env),
        .function_expr => |*f| return try expr_handlers.function(f, env),
        .new_expr => |*n| return try expr_handlers.new(n, env),
        .object => |*o| return try expr_handlers.object(o, env),
        .match_expr => |*m| return try expr_handlers.match(m, env),
        .compound_assignment => |*c| return try expr_handlers.compoundAssignment(c, env),
        .nil => |n| return try expr_handlers.nil(n, env),
    }
}

pub fn evalStmt(stmt: *ast.Stmt, env: *Environment) anyerror!Value {
    switch (stmt.*) {
        .var_decl => |*v| return try stmt_handlers.variable(v, env),
        .expression => |*e| return try stmt_handlers.expression(e, env),
        .block => |*b| return try stmt_handlers.block(b, env),
        .if_stmt => |*i| return try stmt_handlers.conditional(i, env),
        .foreach_stmt => |*f| return try stmt_handlers.foreach(f, env),
        .while_stmt => |*w| return try stmt_handlers.while_loop(w, env),
        .struct_decl => |*c| return try stmt_handlers.structure(c, env),
        .function_decl => |*f| return try stmt_handlers.function(f, env),
        .import_stmt => |*i| return try stmt_handlers.import(i, env),
        .break_stmt => |_| return .break_signal,
        .continue_stmt => |_| return .continue_signal,
        .return_stmt => |*s| return try stmt_handlers.returns(s, env),
        .match_stmt => |*m| return try stmt_handlers.match(m, env),
    }
}
