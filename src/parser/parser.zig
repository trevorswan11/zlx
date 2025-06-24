const std = @import("std");

const token = @import("../lexer/token.zig");
const tokenizer = @import("../lexer/tokenizer.zig");
const ast = @import("ast.zig");
const lus = @import("lookups.zig");
const types = @import("types.zig");
const driver = @import("../utils/driver.zig");

pub const Parser = struct {
    const Self = @This();

    tokens: std.ArrayList(token.Token),
    pos: usize,
    allocator: std.mem.Allocator,
    repl: bool = false,

    pub fn init(allocator: std.mem.Allocator, tokens: std.ArrayList(token.Token), repl: bool) !Self {
        try lus.createTokenLookups(allocator);
        try types.createTypeTokenLookups(allocator);
        return Self{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
            .repl = repl,
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

    pub fn peek(self: *Self) !token.Token {
        return if (self.pos + 1 < self.tokens.items.len) self.tokens.items[self.pos + 1] else return error.IndexOutOfBounds;
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
        const writer_err = driver.getWriterErr();
        const tok = self.currentToken();
        const kind = tok.kind;

        if (kind != expected_kind) {
            try writer_err.print("Expected {s} but received {s} instead at token {d}/{d} @ Line {d}\n", .{
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

    pub fn expectMany(self: *Self, expected_kinds: []const token.TokenKind) !token.Token {
        return try self.expectManyError(expected_kinds, null);
    }

    pub fn expectManyError(self: *Self, expected_kinds: []const token.TokenKind, err: ?anyerror) !token.Token {
        const writer_err = driver.getWriterErr();
        const tok = self.currentToken();
        const kind = tok.kind;

        for (expected_kinds) |expected_kind| {
            if (kind == expected_kind) {
                return self.advance();
            }
        }

        try writer_err.print("Expected one of: ", .{});
        for (expected_kinds, 0..) |expected_kind, i| {
            try writer_err.print("{s}{s}", .{
                if (i > 0) ", " else "",
                try token.tokenKindString(self.allocator, expected_kind),
            });
        }
        try writer_err.print(" but received {s} instead at token {d}/{d} @ Line {d}\n", .{
            try token.tokenKindString(self.allocator, kind),
            self.pos,
            self.tokens.items.len,
            tok.line,
        });

        try tok.debugRuntime();

        if (err) |e| {
            return e;
        } else {
            return error.ParserExpectedKind;
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*ast.Stmt {
    const parseStmt = @import("stmt_parsers.zig").parseStmt;
    var body = std.ArrayList(*ast.Stmt).init(allocator);
    const tokens = try tokenizer.tokenize(allocator, source);
    var parser = try Parser.init(allocator, tokens, false);
    defer parser.deinit();

    while (parser.hasTokens()) {
        const stmt = try parseStmt(&parser);
        const stmt_box = try allocator.create(ast.Stmt);
        stmt_box.* = stmt;
        try body.append(stmt_box);
    }

    const stmt_ptr = try allocator.create(ast.Stmt);
    const block: ast.Stmt = .{
        .block = .{
            .body = body,
        },
    };
    stmt_ptr.* = block;
    return stmt_ptr;
}

pub fn parseREPL(allocator: std.mem.Allocator, source: []const u8) !*ast.Stmt {
    const parseStmt = @import("stmt_parsers.zig").parseStmt;
    var body = std.ArrayList(*ast.Stmt).init(allocator);
    const tokens = try tokenizer.tokenize(allocator, source);
    var parser = try Parser.init(allocator, tokens, true);
    defer parser.deinit();

    while (parser.hasTokens()) {
        const stmt = try parseStmt(&parser);
        const stmt_box = try allocator.create(ast.Stmt);
        stmt_box.* = stmt;
        try body.append(stmt_box);
    }

    const stmt_ptr = try allocator.create(ast.Stmt);
    const block: ast.Stmt = .{
        .block = .{
            .body = body,
        },
    };
    stmt_ptr.* = block;
    return stmt_ptr;
}
