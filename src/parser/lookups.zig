const std = @import("std");

const Parser = @import("parser.zig").Parser;
const ast = @import("../ast/ast.zig");
const token = @import("../lexer/token.zig");
const stmts = @import("stmt.zig");
const exprs = @import("expr.zig");

pub const BindingPower = enum(u32) {
    DEFAULT_BP = 0, // iota
    COMMA,
    ASSIGNMENT,
    LOGICAL,
    RELATIONAL,
    ADDITIVE,
    MULTIPLICATIVE,
    UNARY,
    CALL,
    MEMBER,
    PRIMARY,
};

// === Function pointer types ===
pub const StmtHandler = *const fn (p: *Parser) anyerror!ast.Stmt;
pub const NudHandler = *const fn (p: *Parser) anyerror!ast.Expr;
pub const LedHandler = *const fn (p: *Parser, left: ast.Expr, bp: BindingPower) anyerror!ast.Expr;

// === Lookup Tables ===
pub var bp_lu: std.AutoHashMap(token.TokenKind, BindingPower) = undefined;
pub var nud_lu: std.AutoHashMap(token.TokenKind, NudHandler) = undefined;
pub var led_lu: std.AutoHashMap(token.TokenKind, LedHandler) = undefined;
pub var stmt_lu: std.AutoHashMap(token.TokenKind, StmtHandler) = undefined;

// === Registration functions ===
pub fn led(kind: token.TokenKind, bp: BindingPower, led_fn: LedHandler) !void {
    _ = try bp_lu.put(kind, bp);
    _ = try led_lu.put(kind, led_fn);
}

pub fn nud(kind: token.TokenKind, bp: BindingPower, nud_fn: NudHandler) !void {
    _ = bp;
    _ = try bp_lu.put(kind, BindingPower.PRIMARY);
    _ = try nud_lu.put(kind, nud_fn);
}

pub fn stmt(kind: token.TokenKind, stmt_fn: StmtHandler) !void {
    _ = try bp_lu.put(kind, BindingPower.DEFAULT_BP);
    _ = try stmt_lu.put(kind, stmt_fn);
}

// === Token Lookup Initialization ===
pub fn createTokenLookups(allocator: std.mem.Allocator) !void {
    bp_lu = std.AutoHashMap(token.TokenKind, BindingPower).init(allocator);
    nud_lu = std.AutoHashMap(token.TokenKind, NudHandler).init(allocator);
    led_lu = std.AutoHashMap(token.TokenKind, LedHandler).init(allocator);
    stmt_lu = std.AutoHashMap(token.TokenKind, StmtHandler).init(allocator);

    // Assignment
    try led(token.TokenKind.ASSIGNMENT, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(token.TokenKind.PLUS_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(token.TokenKind.MINUS_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(token.TokenKind.SLASH_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(token.TokenKind.STAR_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(token.TokenKind.PERCENT_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);

    // Logical
    try led(token.TokenKind.AND, .LOGICAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.OR, .LOGICAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.DOT_DOT, .LOGICAL, exprs.parseRangeExpr);

    // Relational
    try led(token.TokenKind.LESS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.LESS_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.GREATER, .RELATIONAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.GREATER_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(token.TokenKind.NOT_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);

    // Additive & Multiplicative
    try led(token.TokenKind.PLUS, .ADDITIVE, exprs.parseBinaryExpr);
    try led(token.TokenKind.MINUS, .ADDITIVE, exprs.parseBinaryExpr);
    try led(token.TokenKind.SLASH, .MULTIPLICATIVE, exprs.parseBinaryExpr);
    try led(token.TokenKind.STAR, .MULTIPLICATIVE, exprs.parseBinaryExpr);
    try led(token.TokenKind.PERCENT, .MULTIPLICATIVE, exprs.parseBinaryExpr);

    // Literals & Symbols
    try nud(token.TokenKind.NUMBER, .PRIMARY, exprs.parsePrimaryExpr);
    try nud(token.TokenKind.STRING, .PRIMARY, exprs.parsePrimaryExpr);
    try nud(token.TokenKind.IDENTIFIER, .PRIMARY, exprs.parsePrimaryExpr);

    // Unary/Prefix
    try nud(token.TokenKind.TYPEOF, .UNARY, exprs.parsePrefixExpr);
    try nud(token.TokenKind.MINUS, .UNARY, exprs.parsePrefixExpr);
    try nud(token.TokenKind.NOT, .UNARY, exprs.parsePrefixExpr);
    try nud(token.TokenKind.OPEN_BRACKET, .PRIMARY, exprs.parseArrayLiteralExpr);

    // Member / Call
    try led(token.TokenKind.DOT, .MEMBER, exprs.parseMemberExpr);
    try led(token.TokenKind.OPEN_BRACKET, .MEMBER, exprs.parseMemberExpr);
    try led(token.TokenKind.OPEN_PAREN, .CALL, exprs.parseCallExpr);

    // Grouping / Functions
    try nud(token.TokenKind.OPEN_PAREN, .DEFAULT_BP, exprs.parseGroupingExpr);
    try nud(token.TokenKind.FN, .DEFAULT_BP, exprs.parseFnExpr);
    try nud(token.TokenKind.NEW, .DEFAULT_BP, struct {
        pub fn afn(p: *Parser) anyerror!ast.Expr {
            _ = p.advance();
            const inst = try exprs.parseExpr(p, .DEFAULT_BP);
            const call_expr_ptr = try p.allocator.create(ast.CallExpr);
            switch (inst) {
                .call => |call_expr| {
                    call_expr_ptr.* = call_expr;
                    return ast.Expr{
                        .new_expr = .{
                            .instantiation = call_expr_ptr,
                        },
                    };
                },
                else => return error.ExpectedCallExpr,
            }
        }
    }.afn);

    // Statements
    try stmt(token.TokenKind.OPEN_CURLY, stmts.parseBlockStmt);
    try stmt(token.TokenKind.LET, stmts.parseVarDeclStmt);
    try stmt(token.TokenKind.CONST, stmts.parseVarDeclStmt);
    try stmt(token.TokenKind.FN, stmts.parseFnDeclaration);
    try stmt(token.TokenKind.IF, stmts.parseIfStmt);
    try stmt(token.TokenKind.IMPORT, stmts.parseImportStmt);
    try stmt(token.TokenKind.FOREACH, stmts.parseForEachStmt);
    try stmt(token.TokenKind.CLASS, stmts.parseClassDeclStmt);
}

pub fn rightBindingPower(bp: BindingPower) BindingPower {
    return @enumFromInt(@intFromEnum(bp) - 1);
}
