const std = @import("std");
const regxp = @import("regxp");

const tokens = @import("token.zig");
const Token = tokens.Token;
const TokenKind = tokens.TokenKind;
const Regex = regxp.Regex;

const LexerError = error{
    Regex,
    IndexOutOfBounds,
    OutOfMemory,
    UnrecognizedToken,
};

pub const RegexHandler = *const fn (lex: *Lexer, regex: *Regex) LexerError!void;

pub const RegexPattern = struct {
    regex: Regex,
    handler: RegexHandler,
};

pub const Lexer = struct {
    const Self = @This();

    pos: usize,
    line: usize,
    source: []const u8,
    tokens: std.ArrayList(Token),
    patterns: std.ArrayList(RegexPattern),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Self {
        return Self{
            .pos = 0,
            .line = 1,
            .source = source,
            .tokens = try std.ArrayList(Token).initCapacity(allocator, 50),
            .patterns = try makePatterns(allocator),
            .allocator = allocator,
        };
    }

    fn makePatterns(allocator: std.mem.Allocator) !std.ArrayList(RegexPattern) {
        var patterns = try std.ArrayList(RegexPattern).initCapacity(allocator, 40);
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\s+"), .handler = skipHandler });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "//.*"), .handler = commentHandler });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\"[^\"]*\""), .handler = stringHandler });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "[0-9]+(\\.[0-9]+)?"), .handler = numberHandler });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "[a-zA-Z_][a-zA-Z0-9_]*"), .handler = symbolHandler });

        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\["), .handler = defaultHandler(.OPEN_BRACKET, "[") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "]"), .handler = defaultHandler(.CLOSE_BRACKET, "]") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\{"), .handler = defaultHandler(.OPEN_CURLY, "{") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "}"), .handler = defaultHandler(.CLOSE_CURLY, "}") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\("), .handler = defaultHandler(.OPEN_PAREN, "(") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\)"), .handler = defaultHandler(.CLOSE_PAREN, ")") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "=="), .handler = defaultHandler(.EQUALS, "==") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "!="), .handler = defaultHandler(.NOT_EQUALS, "!=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "="), .handler = defaultHandler(.ASSIGNMENT, "=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "!"), .handler = defaultHandler(.NOT, "!") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "<="), .handler = defaultHandler(.LESS_EQUALS, "<=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "<"), .handler = defaultHandler(.LESS, "<") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, ">="), .handler = defaultHandler(.GREATER_EQUALS, ">=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, ">"), .handler = defaultHandler(.GREATER, ">") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\|\\|"), .handler = defaultHandler(.OR, "||") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "&&"), .handler = defaultHandler(.AND, "&&") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\.\\."), .handler = defaultHandler(.DOT_DOT, "..") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\."), .handler = defaultHandler(.DOT, ".") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, ";"), .handler = defaultHandler(.SEMI_COLON, ";") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, ":"), .handler = defaultHandler(.COLON, ":") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\?\\?="), .handler = defaultHandler(.NULLISH_ASSIGNMENT, "??=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\?"), .handler = defaultHandler(.QUESTION, "?") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, ","), .handler = defaultHandler(.COMMA, ",") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\+\\+"), .handler = defaultHandler(.PLUS_PLUS, "++") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "--"), .handler = defaultHandler(.MINUS_MINUS, "--") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\+="), .handler = defaultHandler(.PLUS_EQUALS, "+=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "-="), .handler = defaultHandler(.MINUS_EQUALS, "-=") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\+"), .handler = defaultHandler(.PLUS, "+") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "-"), .handler = defaultHandler(.DASH, "-") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "/"), .handler = defaultHandler(.SLASH, "/") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "\\*"), .handler = defaultHandler(.STAR, "*") });
        try patterns.append(.{ .regex = try Regex.compile(allocator, "%"), .handler = defaultHandler(.PERCENT, "%") });

        return patterns;
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
        self.patterns.deinit();
    }

    pub fn advanceN(self: *Self, n: usize) void {
        self.pos += n;
    }

    pub fn push(self: *Self, token: Token) !void {
        try self.tokens.append(token);
    }

    pub fn at(self: *Self) u8 {
        return self.source[self.pos];
    }

    pub fn remainder(self: *Self) []const u8 {
        return self.source[self.pos..];
    }

    pub fn atEOF(self: *Self) bool {
        return self.pos >= self.source.len;
    }
};

pub fn tokenize(source: []const u8) !std.ArrayList(Token) {
    const allocator = std.heap.page_allocator;
    const lex = try Lexer.init(allocator, source);

    while (!lex.atEOF()) {
        var matched = false;
        for (lex.patterns.items) |pattern| {
            if (pattern.regex.match(lex.remainder())) {
                pattern.handler(&lex, pattern.regex);
                matched = true;
                break;
            }
        }

        if (!matched) {
            return LexerError.UnrecognizedToken;
        }
    }

    lex.push(Token.init(std.heap.page_allocator, .EOF, "EOF"));
    return lex.Tokens;
}

pub fn defaultHandler(kind: TokenKind, value: []const u8) RegexHandler {
    return struct {
        fn handler(lex: *Lexer, _: *Regex) LexerError!void {
            lex.advanceN(value.len);
            try lex.push(Token.init(std.heap.page_allocator, kind, value));
        }
    }.handler;
}

fn stringHandler(lex: *Lexer, regex: *regxp.Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const matched = text[span.lower..span.upper];
        try lex.push(Token.init(std.heap.page_allocator, .STRING, matched));
        lex.advanceN(matched.len);
    }
}

fn numberHandler(lex: *Lexer, regex: *regxp.Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const matched = text[span.lower..span.upper];
        try lex.push(Token.init(std.heap.page_allocator, .NUMBER, matched));
        lex.advanceN(matched.len);
    }
}

fn symbolHandler(lex: *Lexer, regex: *regxp.Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const word = text[span.lower..span.upper];

        const kind: TokenKind = tokens.reserved.get(word) orelse .IDENTIFIER;
        try lex.push(Token.init(std.heap.page_allocator, kind, word));
        lex.advanceN(word.len);
    }
}

fn skipHandler(lex: *Lexer, regex: *regxp.Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer caps.deinit();
        const span = caps.boundsAt(0).?;
        lex.advanceN(span.upper);
    }
}

fn commentHandler(lex: *Lexer, regex: *regxp.Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer caps.deinit();
        const span = caps.boundsAt(0).?;
        lex.advanceN(span.upper);
        lex.line += 1;
    }
}
