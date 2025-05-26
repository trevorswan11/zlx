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

pub const RegexHandler = struct {
    ctx: *const anyopaque,
    func: *const fn (*const anyopaque, *Lexer, *Regex) LexerError!void,
};

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
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\s+"),
            .handler = SimpleHandlerWrapper.wrap(skipHandler),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "//.*"),
            .handler = SimpleHandlerWrapper.wrap(commentHandler),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\"[^\"]*\""),
            .handler = SimpleHandlerWrapper.wrap(stringHandler),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "[0-9]+(\\.[0-9]+)?"),
            .handler = SimpleHandlerWrapper.wrap(numberHandler),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "[a-zA-Z_][a-zA-Z0-9_]*"),
            .handler = SimpleHandlerWrapper.wrap(symbolHandler),
        });

        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\["),
            .handler = try defaultHandler(allocator, .OPEN_BRACKET, "["),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "]"),
            .handler = try defaultHandler(allocator, .CLOSE_BRACKET, "]"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\{"),
            .handler = try defaultHandler(allocator, .OPEN_CURLY, "{"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "}"),
            .handler = try defaultHandler(allocator, .CLOSE_CURLY, "}"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\("),
            .handler = try defaultHandler(allocator, .OPEN_PAREN, "("),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\)"),
            .handler = try defaultHandler(allocator, .CLOSE_PAREN, ")"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "=="),
            .handler = try defaultHandler(allocator, .EQUALS, "=="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "!="),
            .handler = try defaultHandler(allocator, .NOT_EQUALS, "!="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "="),
            .handler = try defaultHandler(allocator, .ASSIGNMENT, "="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "!"),
            .handler = try defaultHandler(allocator, .NOT, "!"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "<="),
            .handler = try defaultHandler(allocator, .LESS_EQUALS, "<="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "<"),
            .handler = try defaultHandler(allocator, .LESS, "<"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, ">="),
            .handler = try defaultHandler(allocator, .GREATER_EQUALS, ">="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, ">"),
            .handler = try defaultHandler(allocator, .GREATER, ">"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\|\\|"),
            .handler = try defaultHandler(allocator, .OR, "||"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "&&"),
            .handler = try defaultHandler(allocator, .AND, "&&"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\.\\."),
            .handler = try defaultHandler(allocator, .DOT_DOT, ".."),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\."),
            .handler = try defaultHandler(allocator, .DOT, "."),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, ";"),
            .handler = try defaultHandler(allocator, .SEMI_COLON, ";"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, ":"),
            .handler = try defaultHandler(allocator, .COLON, ":"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\?\\?="),
            .handler = try defaultHandler(allocator, .NULLISH_ASSIGNMENT, "??="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\?"),
            .handler = try defaultHandler(allocator, .QUESTION, "?"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, ","),
            .handler = try defaultHandler(allocator, .COMMA, ","),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\+\\+"),
            .handler = try defaultHandler(allocator, .PLUS_PLUS, "++"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "--"),
            .handler = try defaultHandler(allocator, .MINUS_MINUS, "--"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\+="),
            .handler = try defaultHandler(allocator, .PLUS_EQUALS, "+="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "-="),
            .handler = try defaultHandler(allocator, .MINUS_EQUALS, "-="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\+"),
            .handler = try defaultHandler(allocator, .PLUS, "+"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "-"),
            .handler = try defaultHandler(allocator, .DASH, "-"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "/"),
            .handler = try defaultHandler(allocator, .SLASH, "/"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\*"),
            .handler = try defaultHandler(allocator, .STAR, "*"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "%"),
            .handler = try defaultHandler(allocator, .PERCENT, "%"),
        });

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
    var lex = try Lexer.init(allocator, source);

    while (!lex.atEOF()) {
        var matched = false;
        for (lex.patterns.items) |pattern| {
            if (try @constCast(&pattern.regex).match(lex.remainder())) {
                try pattern.handler.func(pattern.handler.ctx, &lex, @constCast(&pattern.regex));
                matched = true;
                break;
            }
        }

        if (!matched) {
            return LexerError.UnrecognizedToken;
        }
    }

    const tok = Token.init(.EOF, "EOF");
    try lex.push(tok);
    return lex.tokens;
}

const DefaultHandlerCtx = struct {
    kind: TokenKind,
    value: []const u8,

    pub fn call(ctx: *const anyopaque, lex: *Lexer, _: *Regex) LexerError!void {
        const self: *const DefaultHandlerCtx = @alignCast(@ptrCast(ctx));
        try lex.push(Token.init(self.kind, self.value));
        lex.advanceN(self.value.len);
    }
};

pub fn defaultHandler(
    allocator: std.mem.Allocator,
    kind: TokenKind,
    value: []const u8,
) !RegexHandler {
    const ctx = try allocator.create(DefaultHandlerCtx);
    ctx.* = .{
        .kind = kind,
        .value = value,
    };

    return RegexHandler{
        .ctx = ctx,
        .func = DefaultHandlerCtx.call,
    };
}

const SimpleHandlerWrapper = struct {
    const Self = @This();

    pub fn wrap(
        func: *const fn (*Lexer, *Regex) LexerError!void,
    ) RegexHandler {
        const function_ctx: *const anyopaque = @ptrCast(func);
        return RegexHandler{
            .ctx = function_ctx,
            .func = call,
        };
    }

    fn call(ctx: *const anyopaque, lex: *Lexer, regex: *Regex) LexerError!void {
        const real: *const fn (*Lexer, *Regex) LexerError!void = @ptrCast(ctx);
        try real(lex, regex);
    }
};

fn stringHandler(lex: *Lexer, regex: *Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer @constCast(&caps).deinit();

        const span = caps.boundsAt(0).?;
        const matched = text[span.lower..span.upper];
        const tok = Token.init(.STRING, matched);
        try lex.push(tok);
        lex.advanceN(matched.len);
    }
}

fn numberHandler(lex: *Lexer, regex: *Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer @constCast(&caps).deinit();

        const span = caps.boundsAt(0).?;
        const matched = text[span.lower..span.upper];
        const tok = Token.init(.NUMBER, matched);
        try lex.push(tok);
        lex.advanceN(matched.len);
    }
}

fn symbolHandler(lex: *Lexer, regex: *Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer @constCast(&caps).deinit();

        const span = caps.boundsAt(0).?;
        const word = text[span.lower..span.upper];

        const reserved = try Token.getReservedMap(std.heap.page_allocator);
        const kind: TokenKind = reserved.get(word) orelse .IDENTIFIER;
        const tok = Token.init(kind, word);
        try lex.push(tok);
        lex.advanceN(word.len);
    }
}

fn skipHandler(lex: *Lexer, regex: *Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer @constCast(&caps).deinit();
        const span = caps.boundsAt(0).?;
        lex.advanceN(span.upper);
    }
}

fn commentHandler(lex: *Lexer, regex: *Regex) LexerError!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps| {
        defer @constCast(&caps).deinit();
        const span = caps.boundsAt(0).?;
        lex.advanceN(span.upper);
        lex.line += 1;
    }
}
