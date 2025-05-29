const std = @import("std");

// TokenKind
pub const TokenKind = enum(u32) {
    EOF = 0, // iota
    NULL,
    TRUE,
    FALSE,
    NUMBER,
    STRING,
    IDENTIFIER,

    // Grouping & Braces
    OPEN_BRACKET,
    CLOSE_BRACKET,
    OPEN_CURLY,
    CLOSE_CURLY,
    OPEN_PAREN,
    CLOSE_PAREN,

    // Equivalence
    ASSIGNMENT,
    EQUALS,
    NOT_EQUALS,
    NOT,

    // Conditional
    LESS,
    LESS_EQUALS,
    GREATER,
    GREATER_EQUALS,

    // Logical
    OR,
    AND,

    // Symbols
    DOT,
    DOT_DOT,
    SEMI_COLON,
    COLON,
    QUESTION,
    COMMA,

    // Shorthand
    PLUS_PLUS,
    MINUS_MINUS,
    PLUS_EQUALS,
    MINUS_EQUALS,
    SLASH_EQUALS,
    STAR_EQUALS,
    PERCENT_EQUALS,
    NULLISH_ASSIGNMENT, // ??=

    //Maths
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

    // Misc
    NUM_TOKENS,
};

// Token
pub const Token = struct {
    const Self = @This();

    kind: TokenKind,
    value: []const u8,

    pub fn init(kind: TokenKind, value: []const u8) Self {
        return Self{
            .kind = kind,
            .value = value,
        };
    }

    pub fn debug(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.isOneOfMany(@constCast(&[_]TokenKind{ .IDENTIFIER, .NUMBER, .STRING }))) {
            try stdout.print("{s} ({s})\n", .{ try tokenKindString(self.kind), self.value });
        } else {
            try stdout.print("{s} ()\n", .{try tokenKindString(self.kind)});
        }
    }

    pub fn debugRuntime(self: *const Self) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.isOneOfManyRuntime(@constCast(&[_]TokenKind{ .IDENTIFIER, .NUMBER, .STRING }))) {
            try stdout.print("{s} ({s})\n", .{ try tokenKindString(self.kind), self.value });
        } else {
            try stdout.print("{s} ()\n", .{try tokenKindString(self.kind)});
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

    pub fn isOneOfManyRuntime(self: *const Self, expected_tokens: []TokenKind) bool {
        for (expected_tokens) |expected| {
            if (self.kind == expected) {
                return true;
            }
        }
        return false;
    }

    pub fn getReservedMap(allocator: std.mem.Allocator) !std.StringHashMap(TokenKind) {
        var reserved = std.StringHashMap(TokenKind).init(allocator);

        try reserved.put("let", .LET);
        try reserved.put("const", .CONST);
        try reserved.put("class", .CLASS);
        try reserved.put("new", .NEW);
        try reserved.put("import", .IMPORT);
        try reserved.put("from", .FROM);
        try reserved.put("fn", .FN);
        try reserved.put("if", .IF);
        try reserved.put("else", .ELSE);
        try reserved.put("foreach", .FOREACH);
        try reserved.put("while", .WHILE);
        try reserved.put("for", .FOR);
        try reserved.put("export", .EXPORT);
        try reserved.put("typeof", .TYPEOF);
        try reserved.put("in", .IN);

        return reserved;
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
