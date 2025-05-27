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
pub const StmtHandler = fn (p: *Parser) anyerror!ast.Stmt;
pub const NudHandler = fn (p: *Parser) anyerror!ast.Expr;
pub const LedHandler = fn (p: *Parser, left: ast.Expr, bp: BindingPower) anyerror!ast.Expr;

// === Lookup Tables ===
pub var bp_lu: std.AutoHashMap(token.TokenKind, BindingPower) = undefined;
pub var nud_lu: std.AutoHashMap(token.TokenKind, NudHandler) = undefined;
pub var led_lu: std.AutoHashMap(token.TokenKind, LedHandler) = undefined;
pub var stmt_lu: std.AutoHashMap(token.TokenKind, StmtHandler) = undefined;

// === Registration functions ===
pub fn led(kind: token.TokenKind, bp: BindingPower, led_fn: LedHandler) void {
    _ = bp_lu.put(kind, bp);
    _ = led_lu.put(kind, led_fn);
}

pub fn nud(kind: token.TokenKind, bp: BindingPower, nud_fn: NudHandler) void {
    _ = bp;
    _ = bp_lu.put(kind, BindingPower.PRIMARY);
    _ = nud_lu.put(kind, nud_fn);
}

pub fn stmt(kind: token.TokenKind, stmt_fn: StmtHandler) void {
    _ = bp_lu.put(kind, BindingPower.DEFAULT_BP);
    _ = stmt_lu.put(kind, stmt_fn);
}

// === Token Lookup Initialization ===
pub fn createTokenLookups(allocator: std.mem.Allocator) !void {
    bp_lu = std.AutoHashMap(token.TokenKind, BindingPower).init(allocator);
    nud_lu = std.AutoHashMap(token.TokenKind, NudHandler).init(allocator);
    led_lu = std.AutoHashMap(token.TokenKind, LedHandler).init(allocator);
    stmt_lu = std.AutoHashMap(token.TokenKind, StmtHandler).init(allocator);

    // Assignment
    led(token.TokenKind.ASSIGNMENT, .ASSIGNMENT, exprs.parseAssignmentExpr);
    led(token.TokenKind.PLUS_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);
    led(token.TokenKind.MINUS_EQUALS, .ASSIGNMENT, exprs.parseAssignmentExpr);

    // Logical
    led(token.TokenKind.AND, .LOGICAL, exprs.parseBinaryExpr);
    led(token.TokenKind.OR, .LOGICAL, exprs.parseBinaryExpr);
    led(token.TokenKind.DOT_DOT, .LOGICAL, exprs.parseRangeExpr);

    // Relational
    led(token.TokenKind.LESS, .RELATIONAL, exprs.parseBinaryExpr);
    led(token.TokenKind.LESS_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    led(token.TokenKind.GREATER, .RELATIONAL, exprs.parseBinaryExpr);
    led(token.TokenKind.GREATER_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    led(token.TokenKind.EQUALS, .RELATIONAL, exprs.parseBinaryExpr);
    led(token.TokenKind.NOT_EQUALS, .RELATIONAL, exprs.parseBinaryExpr);

    // Additive & Multiplicative
    led(token.TokenKind.PLUS, .ADDITIVE, exprs.parseBinaryExpr);
    led(token.TokenKind.DASH, .ADDITIVE, exprs.parseBinaryExpr);
    led(token.TokenKind.SLASH, .MULTIPLICATIVE, exprs.parseBinaryExpr);
    led(token.TokenKind.STAR, .MULTIPLICATIVE, exprs.parseBinaryExpr);
    led(token.TokenKind.PERCENT, .MULTIPLICATIVE, exprs.parseBinaryExpr);

    // Literals & Symbols
    nud(token.TokenKind.NUMBER, .PRIMARY, exprs.parsePrimaryExpr);
    nud(token.TokenKind.STRING, .PRIMARY, exprs.parsePrimaryExpr);
    nud(token.TokenKind.IDENTIFIER, .PRIMARY, exprs.parsePrimaryExpr);

    // Unary/Prefix
    nud(token.TokenKind.TYPEOF, .UNARY, exprs.parsePrefixExpr);
    nud(token.TokenKind.DASH, .UNARY, exprs.parsePrefixExpr);
    nud(token.TokenKind.NOT, .UNARY, exprs.parsePrefixExpr);
    nud(token.TokenKind.OPEN_BRACKET, .PRIMARY, exprs.parseArrayLiteralExpr);

    // Member / Call
    led(token.TokenKind.DOT, .MEMBER, exprs.parseMemberExpr);
    led(token.TokenKind.OPEN_BRACKET, .MEMBER, exprs.parseMemberExpr);
    led(token.TokenKind.OPEN_PAREN, .CALL, exprs.parseCallExpr);

    // Grouping / Functions
    nud(token.TokenKind.OPEN_PAREN, .DEFAULT_BP, exprs.parseGroupingExpr);
    nud(token.TokenKind.FN, .DEFAULT_BP, exprs.parseFnExpr);
    nud(token.TokenKind.NEW, .DEFAULT_BP, struct {
        pub fn afn(p: *Parser) anyerror!ast.Expr {
            _ = p.advance();
            const inst = try exprs.parseExpr(p, .DEFAULT_BP);
            return switch (inst) {
                .call => |call_expr| ast.Expr{
                    .new_expr = .{
                        .instantiation = call_expr,
                    },
                },
                else => error.ExpectedCallExpr,
            };
        }
    }.afn);

    // Statements
    stmt(token.TokenKind.OPEN_CURLY, stmts.parseBlockStmt);
    stmt(token.TokenKind.LET, stmts.parseVarDeclStmt);
    stmt(token.TokenKind.CONST, stmts.parseVarDeclStmt);
    stmt(token.TokenKind.FN, stmts.parseFnDeclaration);
    stmt(token.TokenKind.IF, stmts.parseIfStmt);
    stmt(token.TokenKind.IMPORT, stmts.parseImportStmt);
    stmt(token.TokenKind.FOREACH, stmts.parseForEachStmt);
    stmt(token.TokenKind.CLASS, stmts.parseClassDeclarationStmt);
}
