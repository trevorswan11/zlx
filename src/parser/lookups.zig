const std = @import("std");

const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const token = @import("../lexer/token.zig");
const stmts = @import("stmt.zig");
const exprs = @import("expr.zig");
const driver = @import("../utils/driver.zig");

pub const BindingPower = struct {
    left: u32,
    right: u32,
};

pub const binding = struct {
    pub const DEFAULT_BP = BindingPower{
        .left = 0,
        .right = 0,
    };
    pub const COMMA = BindingPower{
        .left = 1,
        .right = 2,
    };
    pub const ASSIGNMENT = BindingPower{
        .left = 3,
        .right = 2,
    };
    pub const LOGICAL = BindingPower{
        .left = 5,
        .right = 6,
    };
    pub const RELATIONAL = BindingPower{
        .left = 10,
        .right = 11,
    };
    pub const ADDITIVE = BindingPower{
        .left = 20,
        .right = 21,
    };
    pub const MULTIPLICATIVE = BindingPower{
        .left = 30,
        .right = 31,
    };
    pub const UNARY = BindingPower{
        .left = 40,
        .right = 41,
    };
    pub const CALL = BindingPower{
        .left = 50,
        .right = 51,
    };
    pub const MEMBER = BindingPower{
        .left = 60,
        .right = 61,
    };
    pub const PRIMARY = BindingPower{
        .left = 70,
        .right = 71,
    };
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

pub fn nud(kind: token.TokenKind, _: BindingPower, nud_fn: NudHandler) !void {
    _ = try bp_lu.put(kind, binding.PRIMARY);
    _ = try nud_lu.put(kind, nud_fn);
}

pub fn stmt(kind: token.TokenKind, stmt_fn: StmtHandler) !void {
    _ = try bp_lu.put(kind, binding.DEFAULT_BP);
    _ = try stmt_lu.put(kind, stmt_fn);
}

// === Token Lookup Initialization ===
pub fn createTokenLookups(allocator: std.mem.Allocator) !void {
    bp_lu = std.AutoHashMap(token.TokenKind, BindingPower).init(allocator);
    nud_lu = std.AutoHashMap(token.TokenKind, NudHandler).init(allocator);
    led_lu = std.AutoHashMap(token.TokenKind, LedHandler).init(allocator);
    stmt_lu = std.AutoHashMap(token.TokenKind, StmtHandler).init(allocator);

    // Assignment
    try led(.ASSIGNMENT, binding.ASSIGNMENT, exprs.parseAssignmentExpr);
    try led(.PLUS_EQUALS, binding.ASSIGNMENT, exprs.parseCompoundAssignmentExpr);
    try led(.MINUS_EQUALS, binding.ASSIGNMENT, exprs.parseCompoundAssignmentExpr);
    try led(.SLASH_EQUALS, binding.ASSIGNMENT, exprs.parseCompoundAssignmentExpr);
    try led(.STAR_EQUALS, binding.ASSIGNMENT, exprs.parseCompoundAssignmentExpr);
    try led(.PERCENT_EQUALS, binding.ASSIGNMENT, exprs.parseCompoundAssignmentExpr);

    // Logical
    try led(.AND, binding.LOGICAL, exprs.parseBinaryExpr);
    try led(.OR, binding.LOGICAL, exprs.parseBinaryExpr);
    try led(.BITWISE_AND, binding.LOGICAL, exprs.parseBinaryExpr);
    try led(.BITWISE_OR, binding.LOGICAL, exprs.parseBinaryExpr);
    try led(.BITWISE_XOR, binding.LOGICAL, exprs.parseBinaryExpr);
    try led(.DOT_DOT, binding.LOGICAL, exprs.parseRangeExpr);

    // Relational
    try led(.LESS, binding.RELATIONAL, exprs.parseBinaryExpr);
    try led(.LESS_EQUALS, binding.RELATIONAL, exprs.parseBinaryExpr);
    try led(.GREATER, binding.RELATIONAL, exprs.parseBinaryExpr);
    try led(.GREATER_EQUALS, binding.RELATIONAL, exprs.parseBinaryExpr);
    try led(.EQUALS, binding.RELATIONAL, exprs.parseBinaryExpr);
    try led(.NOT_EQUALS, binding.RELATIONAL, exprs.parseBinaryExpr);

    // Additive & Multiplicative
    try led(.PLUS, binding.ADDITIVE, exprs.parseBinaryExpr);
    try led(.MINUS, binding.ADDITIVE, exprs.parseBinaryExpr);
    try nud(.MINUS_MINUS, binding.UNARY, exprs.parsePrefixExpr);
    try nud(.PLUS_PLUS, binding.UNARY, exprs.parsePrefixExpr);
    try led(.SLASH, binding.MULTIPLICATIVE, exprs.parseBinaryExpr);
    try led(.STAR, binding.MULTIPLICATIVE, exprs.parseBinaryExpr);
    try led(.PERCENT, binding.MULTIPLICATIVE, exprs.parseBinaryExpr);

    // Literals & Symbols
    try nud(.NUMBER, binding.PRIMARY, exprs.parsePrimaryExpr);
    try nud(.STRING, binding.PRIMARY, exprs.parsePrimaryExpr);
    try nud(.IDENTIFIER, binding.PRIMARY, exprs.parsePrimaryExpr);
    _ = try nud_lu.put(.NIL, exprs.parseNilExpr);

    // Unary/Prefix
    try nud(.TYPEOF, binding.UNARY, exprs.parsePrefixExpr);
    _ = try nud_lu.put(.MINUS, exprs.parsePrefixExpr);
    try nud(.NOT, binding.UNARY, exprs.parsePrefixExpr);
    try nud(.OPEN_BRACKET, binding.PRIMARY, exprs.parseArrayLiteralExpr);
    try nud_lu.put(.MATCH, exprs.parseMatchExpr);

    // Object Literal
    _ = try nud_lu.put(.OPEN_CURLY, exprs.parseObjectLiteral);

    // Member / Call
    try led(.DOT, binding.MEMBER, exprs.parseMemberExpr);
    try led(.OPEN_BRACKET, binding.MEMBER, exprs.parseMemberExpr);
    try led(.OPEN_PAREN, binding.CALL, exprs.parseCallExpr);

    // Grouping / Functions
    try nud(.OPEN_PAREN, binding.DEFAULT_BP, exprs.parseGroupingExpr);
    try nud(.FN, binding.DEFAULT_BP, exprs.parseFnExpr);
    try nud(.NEW, binding.DEFAULT_BP, struct {
        pub fn afn(p: *Parser) anyerror!ast.Expr {
            _ = p.advance();
            const inst = try exprs.parseExpr(p, binding.DEFAULT_BP);
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
                else => {
                    const writer_err = driver.getWriterErr();
                    try writer_err.print("Expected call expression with new keyword but found expression: {s}\n", .{@tagName(inst)});
                    return error.ExpectedCallExpr;
                },
            }
        }
    }.afn);

    // Booleans
    try nud(.TRUE, binding.PRIMARY, exprs.parseBooleanLiteral);
    try nud(.FALSE, binding.PRIMARY, exprs.parseBooleanLiteral);

    // Statements
    _ = try stmt_lu.put(.OPEN_CURLY, stmts.parseBlockStmt);
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
    try stmt(.RETURN, stmts.parseReturnStmt);
    try stmt(.MATCH, stmts.parseMatchStmt);
}
