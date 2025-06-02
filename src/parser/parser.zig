const std = @import("std");

const token = @import("../lexer/token.zig");
const tokenizer = @import("../lexer/tokenizer.zig");
const ast = @import("../ast/ast.zig");
const lus = @import("lookups.zig");
const types = @import("types.zig");

pub const Parser = struct {
    const Self = @This();

    // errors: []error{},
    tokens: std.ArrayList(token.Token),
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: std.ArrayList(token.Token)) !Self {
        try lus.createTokenLookups(allocator);
        try types.createTypeTokenLookups(allocator);
        return Self{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn numTokens(self: *Self) usize {
        return self.tokens.items.len;
    }

    pub fn currentToken(self: *Self) token.Token {
        return self.tokens.items[self.pos];
    }

    pub fn currentTokenKind(self: *Self) token.TokenKind {
        return self.currentToken().kind;
    }

    pub fn match(self: *Parser, kind: token.TokenKind) bool {
        return self.currentTokenKind() == kind;
    }

    pub fn advance(self: *Self) token.Token {
        const tok = self.currentToken();
        self.pos += 1;
        return tok;
    }

    pub fn hasTokens(self: *Self) bool {
        return self.pos < self.tokens.items.len and self.currentTokenKind() != token.TokenKind.EOF;
    }

    pub fn expect(self: *Self, expected_kind: token.TokenKind) !token.Token {
        return try self.expectError(expected_kind, null);
    }

    pub fn expectError(self: *Self, expected_kind: token.TokenKind, err: ?anyerror) !token.Token {
        const stderr = std.io.getStdErr().writer();
        const tok = self.currentToken();
        const kind = tok.kind;

        if (kind != expected_kind) {
            try stderr.print("Expected {s} but received {s} instead at token {d}/{d} @ Line {d}\n", .{
                try token.tokenKindString(self.allocator, expected_kind),
                try token.tokenKindString(self.allocator, kind),
                self.pos,
                self.tokens.items.len,
                self.tokens.items[self.pos].line,
            });
            try self.currentToken().debugRuntime();
            if (err) |e| {
                return e;
            } else {
                return error.ParserExpectedKind;
            }
        }

        return self.advance();
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*ast.Stmt {
    const parseStmt = @import("stmt.zig").parseStmt;
    var body = std.ArrayList(*ast.Stmt).init(allocator);
    const tokens = try tokenizer.tokenize(allocator, source);
    var parser = try Parser.init(allocator, tokens);
    defer parser.deinit();

    while (parser.hasTokens()) {
        const stmt = try parseStmt(&parser);
        const stmt_box = try allocator.create(ast.Stmt);
        stmt_box.* = stmt;
        try body.append(stmt_box);
    }

    const stmt_ptr = try allocator.create(ast.Stmt);
    const block = ast.Stmt{
        .block = ast.BlockStmt{
            .body = body,
        },
    };
    stmt_ptr.* = block;
    return stmt_ptr;
}
