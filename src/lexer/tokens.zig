const std = @import("std");

// TokenKind
pub const TokenKind = enum(i64) {
    EOF = 0, // iota
    NUMBER,
    STRING,
    IDENTIFIER,

    OPEN_BRACKET,
    CLOSED_BRACKET,
    OPEN_CURLY,
    CLOSED_CURLY,
    OPEN_PAREN,
    CLOSED_PAREN,

    ASSIGNMENT, // =
    EQUALS, // ==
    NOT,
    NOT_EQUALS,

    LESS,
    LESS_EQUALS,
    GREATER,
    GREATER_EQUALS,

    OR,
    AND,

    DOT,
    DOT_DOT,
    SEMI_COLON,
    COLON,
    QUESTION,
    COMMA,

    PLUS_PLUS,
    MINUS_MINUS,
    PLUS_EQUALS,
    MINUS_EQUALS,
    
    PLUS,
    DASH,
    SLASH,
    STAR,
    PERCENT,

    // Reserved Keywords
    LET,
    CONST,
    CLASS,
    NEW,
    IMPORT,
    FROM,
    FN,
    IF,
    ELSE,
    FOREACH,
    WHILE,
    FOR,
    EXPORT,
    TYPEOF,
    IN,
};

// Token
pub const Token = struct {
    const Self = @This();

    kind: TokenKind,
    value: []const u8,

    pub fn Debug(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.isOneOfMany(&[_]TokenKind{ .IDENTIFIER, .NUMBER, .STRING })) {
            try stdout.print("{s} ({s})\n", tokenKindString(self.kind), self.value);
        } else {
            try stdout.print("{s} ()\n", tokenKindString(self.kind));
        }
    }

    pub fn isOneOfMany(self: *Self, expected_tokens: []TokenKind) bool {
        for (expected_tokens) |expected| {
            if (self.kind == expected) {
                return true;
            }
        }
        return false;
    }
};

pub fn tokenKindString(kind: TokenKind) ![]const u8 {
        const tag = @tagName(kind);
        var buffer = try std.heap.page_allocator.alloc(u8, tag.len);
        for (tag, 0..) |c, i| {
            buffer[i] = std.ascii.toLower(c);
        }
        return tag;
    }

pub fn NewToken(kind: TokenKind, value: []const u8) Token {
    return Token{
        .kind = kind,
        .value = value,
    };
}

