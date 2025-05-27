const std = @import("std");

const token = @import("../lexer/token.zig");
const ast = @import("../ast/ast.zig");
const lus = @import("lookups.zig");

const stderr = std.io.getStdErr().writer();

pub const Parser = struct {
    const Self = @This();

    // errors: []error{},
    tokens: std.ArrayList(token.Token),
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        try lus.createTokenLookups(allocator);
        return Self{
            .tokens = try std.ArrayList(token.Token).init(allocator),
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
        const tok = self.currentToken();
        const kind = tok.kind;

        if (kind != expected_kind) {
            if (err) |e| {
                return e;
            } else {
                try stderr.print("Expected {s} but received {s} instead\n", .{
                    token.tokenKindString(expected_kind),
                    token.tokenKindString(kind),
                });
                return error.ParserExpectedKind;
            }
        }

        return self.advance();
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []token.Token) !ast.Stmt {
    const parseStmt = @import("stmt.zig").parseStmt;
    var body = try std.ArrayList(ast.Stmt).init(allocator);
    var parser = try Parser.init(allocator);
    defer parser.deinit();
    try parser.tokens.appendSlice(tokens);

    while (parser.hasTokens()) {
        try body.append(parseStmt(&parser));
    }

    return ast.Stmt{
        .block = ast.BlockStmt{
            .body = body,
        },
    };
}
