const std = @import("std");
const regxp = @import("regxp");

const token = @import("token.zig");
const driver = @import("../utils/driver.zig");

const Token = token.Token;
const TokenKind = token.TokenKind;
const Regex = regxp.Regex;

pub const RegexHandler = struct {
    ctx: *const anyopaque,
    func: *const fn (*const anyopaque, *Lexer, *Regex) anyerror!void,
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
        _ = try Token.getReservedMap(allocator);
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
            .regex = try Regex.compile(allocator, "//[^\n]*"),
            .handler = SimpleHandlerWrapper.wrap(commentHandler),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "```[\\s\\S]*?```"),
            .handler = SimpleHandlerWrapper.wrap(multilineStringHandler),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\"(\\\\.|[^\"])*\""),
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
            .regex = try Regex.compile(allocator, "=>"),
            .handler = try defaultHandler(allocator, .ARROW, "=>"),
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
            .regex = try Regex.compile(allocator, "\\|"),
            .handler = try defaultHandler(allocator, .BITWISE_OR, "|"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "&&"),
            .handler = try defaultHandler(allocator, .AND, "&&"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "&"),
            .handler = try defaultHandler(allocator, .BITWISE_AND, "&"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\^"),
            .handler = try defaultHandler(allocator, .BITWISE_XOR, "^"),
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
            .regex = try Regex.compile(allocator, "/="),
            .handler = try defaultHandler(allocator, .SLASH_EQUALS, "/="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\*="),
            .handler = try defaultHandler(allocator, .STAR_EQUALS, "*="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "%="),
            .handler = try defaultHandler(allocator, .PERCENT_EQUALS, "%="),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\+"),
            .handler = try defaultHandler(allocator, .PLUS, "+"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "-"),
            .handler = try defaultHandler(allocator, .MINUS, "-"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "/"),
            .handler = try defaultHandler(allocator, .SLASH, "/"),
        });
        try patterns.append(.{
            .regex = try Regex.compile(allocator, "\\*\\*"),
            .handler = try defaultHandler(allocator, .STAR_STAR, "**"),
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

    pub fn push(self: *Self, tok: Token) !void {
        try self.tokens.append(tok);
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

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(Token) {
    var lex = try Lexer.init(allocator, source);
    const writer_err = driver.getWriterErr();

    while (!lex.atEOF()) {
        var matched = false;
        for (lex.patterns.items) |pattern_const| {
            var pattern = pattern_const;
            if (try pattern.regex.match(lex.remainder())) {
                try pattern.handler.func(pattern.handler.ctx, &lex, &pattern.regex); // This must advance the lexer's position
                matched = true;
                break;
            }
        }

        if (!matched) {
            try writer_err.print("Character {c} at position {d} was not recognized as a valid token @ Line {d}\n", .{ lex.source[lex.pos], lex.pos, lex.line });
            return error.UnrecognizedToken;
        }
    }

    const tok = Token.init(allocator, .EOF, "EOF", lex.line, source.len, source.len);
    try lex.push(tok);
    return lex.tokens;
}

const DefaultHandlerCtx = struct {
    kind: TokenKind,
    value: []const u8,

    pub fn call(ctx: *const anyopaque, lex: *Lexer, _: *Regex) anyerror!void {
        const self: *const DefaultHandlerCtx = @alignCast(@ptrCast(ctx));
        const start = lex.pos;
        const end = start + self.value.len;
        try lex.push(Token.init(lex.allocator, self.kind, self.value, lex.line, start, end));
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
        func: *const fn (*Lexer, *Regex) anyerror!void,
    ) RegexHandler {
        const function_ctx: *const anyopaque = @ptrCast(func);
        return RegexHandler{
            .ctx = function_ctx,
            .func = call,
        };
    }

    fn call(ctx: *const anyopaque, lex: *Lexer, regex: *Regex) anyerror!void {
        const real: *const fn (*Lexer, *Regex) anyerror!void = @ptrCast(@alignCast(ctx));
        try real(lex, regex);
    }
};

fn stringHandler(lex: *Lexer, regex: *Regex) anyerror!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps_const| {
        var caps = caps_const;
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const raw = text[(span.lower + 1)..(span.upper - 1)];
        const unescaped = try driver.unescapeString(lex.allocator, raw);

        const start = lex.pos + span.lower;
        const end = lex.pos + span.upper;

        const tok = Token.init(lex.allocator, .STRING, unescaped, lex.line, start, end);
        try lex.push(tok);
        lex.advanceN(raw.len + 2);
    }
}

fn multilineStringHandler(lex: *Lexer, regex: *Regex) anyerror!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps_const| {
        var caps = caps_const;
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const raw = text[(span.lower + 3)..(span.upper - 3)];
        const unescaped = try driver.unescapeString(lex.allocator, raw);

        const start = lex.pos + span.lower;
        const end = lex.pos + span.upper;

        const tok = Token.init(lex.allocator, .STRING, unescaped, lex.line, start, end);
        try lex.push(tok);
        lex.advanceN(span.upper);
        lex.line += countNewlines(text[span.lower..span.upper]);
    }
}

fn numberHandler(lex: *Lexer, regex: *Regex) anyerror!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps_const| {
        var caps = caps_const;
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const matched = text[span.lower..span.upper];

        const start = lex.pos + span.lower;
        const end = lex.pos + span.upper;

        const tok = Token.init(lex.allocator, .NUMBER, matched, lex.line, start, end);
        try lex.push(tok);
        lex.advanceN(matched.len);
    }
}

fn symbolHandler(lex: *Lexer, regex: *Regex) anyerror!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps_const| {
        var caps = caps_const;
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        const word = text[span.lower..span.upper];

        const start = lex.pos + span.lower;
        const end = lex.pos + span.upper;

        const reserved_map = try Token.getReservedMap(lex.allocator);
        std.debug.assert(@intFromPtr(reserved_map) % @alignOf(std.StringHashMap(TokenKind)) == 0);
        const kind: TokenKind = reserved_map.get(word) orelse .IDENTIFIER;
        const tok = Token.init(lex.allocator, kind, word, lex.line, start, end);
        try lex.push(tok);
        lex.advanceN(word.len);
    }
}

fn skipHandler(lex: *Lexer, regex: *Regex) anyerror!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps_const| {
        var caps = caps_const;
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        lex.advanceN(span.upper);
        lex.line += countNewlines(text[span.lower..span.upper]);
    }
}

fn commentHandler(lex: *Lexer, regex: *Regex) anyerror!void {
    const text = lex.remainder();
    if (try regex.captures(text)) |caps_const| {
        var caps = caps_const;
        defer caps.deinit();

        const span = caps.boundsAt(0).?;
        lex.advanceN(span.upper);
        if (text[span.upper - 1] == '\n') {
            lex.line += 1;
        }
    }
}

fn countNewlines(slice: []const u8) usize {
    var count: usize = 0;
    for (slice) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}
