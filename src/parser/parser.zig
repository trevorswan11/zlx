const std = @import("std");

const token = @import("../lexer/token.zig");
const ast = @import("../ast/ast.zig");

pub const Parser = struct {
    const Self = @This();

    // errors: []error{},
    tokens: std.ArrayList(token.Token),
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .tokens = try std.ArrayList(token.Token).init(allocator),
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
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
};

pub fn parse(allocator: std.mem.Allocator, tokens: []token.Token) !ast.Stmt {
    const parseStmt = @import("stmt.zig").parseStmt;
    var body = try std.ArrayList(ast.Stmt).initCapacity(allocator, 10);
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