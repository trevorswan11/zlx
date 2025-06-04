const std = @import("std");

const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
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
    try led(.ASSIGNMENT, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(.PLUS_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(.MINUS_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(.SLASH_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(.STAR_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(.PERCENT_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);

    // Logical
    try led(.AND, .LOGICAL, exprs.parseBinaryExpr);
    try led(.OR, .LOGICAL, exprs.parseBinaryExpr);
    try led(.DOT_DOT, .LOGICAL, exprs.parseRangeExpr);

    // Relational
    try led(.LESS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(.LESS_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(.GREATER, .RELATIONAL, exprs.parseBinaryExpr);
    try led(.GREATER_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(.EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    try led(.NOT_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);

    // Additive & Multiplicative
    try led(.PLUS, .ADDITIVE, exprs.parseBinaryExpr);
    try led(.MINUS, .ADDITIVE, exprs.parseBinaryExpr);
    try nud(.MINUS_MINUS, .UNARY, exprs.parsePrefixExpr);
    try nud(.PLUS_PLUS, .UNARY, exprs.parsePrefixExpr);
    try led(.SLASH, .MULTIPLICATIVE, exprs.parseBinaryExpr);
    try led(.STAR, .MULTIPLICATIVE, exprs.parseBinaryExpr);
    try led(.PERCENT, .MULTIPLICATIVE, exprs.parseBinaryExpr);

    // Literals & Symbols
    try nud(.NUMBER, .PRIMARY, exprs.parsePrimaryExpr);
    try nud(.STRING, .PRIMARY, exprs.parsePrimaryExpr);
    try nud(.IDENTIFIER, .PRIMARY, exprs.parsePrimaryExpr);

    // Unary/Prefix
    try nud(.TYPEOF, .UNARY, exprs.parsePrefixExpr);
    try nud(.MINUS, .UNARY, exprs.parsePrefixExpr);
    try nud(.NOT, .UNARY, exprs.parsePrefixExpr);
    try nud(.OPEN_BRACKET, .PRIMARY, exprs.parseArrayLiteralExpr);

    // Object Literal
    try nud(.OPEN_CURLY, .PRIMARY, exprs.parseObjectLiteral);

    // Member / Call
    try led(.DOT, .MEMBER, exprs.parseMemberExpr);
    try led(.OPEN_BRACKET, .MEMBER, exprs.parseMemberExpr);
    try led(.OPEN_PAREN, .CALL, exprs.parseCallExpr);

    // Grouping / Functions
    try nud(.OPEN_PAREN, .DEFAULT_BP, exprs.parseGroupingExpr);
    try nud(.FN, .DEFAULT_BP, exprs.parseFnExpr);
    try nud(.NEW, .DEFAULT_BP, struct {
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

    // Booleans
    try nud(.TRUE, .PRIMARY, exprs.parseBooleanLiteral);
    try nud(.FALSE, .PRIMARY, exprs.parseBooleanLiteral);

    // Statements
    try stmt(.OPEN_CURLY, stmts.parseBlockStmt);
    try stmt(.LET, stmts.parseVarDeclStmt);
    try stmt(.CONST, stmts.parseVarDeclStmt);
    try stmt(.FN, stmts.parseFnDeclaration);
    try stmt(.IF, stmts.parseIfStmt);
    try stmt(.IMPORT, stmts.parseImportStmt);
    try stmt(.FOREACH, stmts.parseForEachStmt);
    try stmt(.WHILE, stmts.parseWhileStmt);
    try stmt(.CLASS, stmts.parseClassDeclStmt);
    try stmt(.BREAK, stmts.parseBreakStmt);
    try stmt(.CONTINUE, stmts.parseContinueStmt);
}
