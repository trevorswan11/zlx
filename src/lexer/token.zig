const std = @import("std");

const driver = @import("../utils/driver.zig");

// TokenKind
pub const TokenKind = enum(u32) {
    EOF = 0,
    NIL,
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
    BITWISE_OR,
    BITWISE_AND,
    BITWISE_XOR,

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

    //Math
    PLUS,
    MINUS,
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
    TYPEOF,
    DELETE,
    IN,
    BREAK,
    CONTINUE,
    RETURN,
    MATCH,
    ARROW,
};

// Token
pub const Token = struct {
    const Self = @This();

    kind: TokenKind,
    value: []const u8,
    allocator: std.mem.Allocator,
    line: usize,
    start: usize,
    end: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        kind: TokenKind,
        value: []const u8,
        line: usize,
        start: usize,
        end: usize,
    ) Self {
        return Self{
            .kind = kind,
            .value = value,
            .allocator = allocator,
            .line = line,
            .start = start,
            .end = end,
        };
    }

    pub fn debug(self: *Self) !void {
        const writer_out = driver.getWriterOut();
        try writer_out.print("Token Line #: {d}\n", .{self.line});
        if (self.isOneOfMany(&[_]TokenKind{ .IDENTIFIER, .NUMBER, .STRING })) {
            try writer_out.print("{s} ({s})\n", .{ try tokenKindString(self.allocator, self.kind), self.value });
        } else {
            try writer_out.print("{s} ()\n", .{try tokenKindString(self.allocator, self.kind)});
        }
    }

    pub fn debugRuntime(self: *const Self) !void {
        const writer_out = driver.getWriterOut();
        try writer_out.print("Token Line #: {d}\n", .{self.line});
        if (self.isOneOfManyRuntime(&[_]TokenKind{ .IDENTIFIER, .NUMBER, .STRING })) {
            try writer_out.print("{s} ({s})\n", .{ try tokenKindString(self.allocator, self.kind), self.value });
        } else {
            try writer_out.print("{s} ()\n", .{try tokenKindString(self.allocator, self.kind)});
        }
    }

    pub fn isOneOfMany(self: *Self, expected_tokens: []const TokenKind) bool {
        for (expected_tokens) |expected| {
            if (self.kind == expected) {
                return true;
            }
        }
        return false;
    }

    pub fn isOneOfManyRuntime(self: *const Self, expected_tokens: []const TokenKind) bool {
        for (expected_tokens) |expected| {
            if (self.kind == expected) {
                return true;
            }
        }
        return false;
    }

    pub fn getReservedMap(allocator: std.mem.Allocator) !std.StringHashMap(TokenKind) {
        var reserved = std.StringHashMap(TokenKind).init(allocator);

        // Keywords
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
        try reserved.put("return", .RETURN);
        try reserved.put("break", .BREAK);
        try reserved.put("continue", .CONTINUE);
        try reserved.put("typeof", .TYPEOF);
        try reserved.put("delete", .DELETE);
        try reserved.put("in", .IN);
        try reserved.put("true", .TRUE);
        try reserved.put("false", .FALSE);
        try reserved.put("match", .MATCH);
        try reserved.put("nil", .NIL);

        // Built-in functions
        try reserved.put("print", .IDENTIFIER);
        try reserved.put("println", .IDENTIFIER);
        try reserved.put("len", .IDENTIFIER);
        try reserved.put("ref", .IDENTIFIER);
        try reserved.put("range", .IDENTIFIER);
        try reserved.put("to_string", .IDENTIFIER);
        try reserved.put("to_number", .IDENTIFIER);
        try reserved.put("to_bool", .IDENTIFIER);

        // Built-in modules
        try reserved.put("array", .IDENTIFIER);
        try reserved.put("debug", .IDENTIFIER);
        try reserved.put("fs", .IDENTIFIER);
        try reserved.put("math", .IDENTIFIER);
        try reserved.put("path", .IDENTIFIER);
        try reserved.put("random", .IDENTIFIER);
        try reserved.put("string", .IDENTIFIER);
        try reserved.put("sys", .IDENTIFIER);
        try reserved.put("time", .IDENTIFIER);

        return reserved;
    }

    pub fn isReservedIdentifier(reserved: *const std.StringHashMap(TokenKind), ident: []const u8) bool {
        return reserved.get(ident) != null;
    }
};

pub fn tokenKindString(allocator: std.mem.Allocator, kind: TokenKind) ![]const u8 {
    const tag = @tagName(kind);
    var buffer = try allocator.alloc(u8, tag.len);
    for (tag, 0..) |c, i| {
        buffer[i] = std.ascii.toLower(c);
    }
    return tag;
}
