const std = @import("std");

const token = @import("../lexer/token.zig");
const driver = @import("driver.zig");

const TokenKind = token.TokenKind;

const colors = struct {
    pub const reset = "\x1b[0m";

    pub const keyword = "\x1b[38;2;153;102;204m"; // light magenta
    pub const string = "\x1b[38;2;255;191;0m"; // orange-yellow
    pub const number = "\x1b[38;2;200;255;200m"; // very light green
    pub const boolean = "\x1b[34m"; // solid blue
    pub const nullish = "\x1b[36m"; // cyan

    pub const operator = "\x1b[97m"; // white
    pub const identifier = "\x1b[38;2;0;183;235m"; // muted blue
    pub const function = "\x1b[38;2;220;220;160m"; // soft light yellow
    pub const punctuation = "\x1b[97m"; // bright cyan
    pub const comment = "\x1b[32m"; // green
};

fn colorForKind(kind: TokenKind) []const u8 {
    return switch (kind) {
        // Core keywords
        .IF, .ELSE, .WHILE, .FOR, .FOREACH, .BREAK, .CONTINUE => colors.keyword,
        .IMPORT, .FROM, .TYPEOF, .DELETE => colors.keyword,
        .LET, .CONST, .FN, .STRUCT, .NEW, .IN, .RETURN, .MATCH, .ENUM => colors.keyword,

        // Literals
        .TRUE, .FALSE => colors.boolean,
        .NIL => colors.nullish,
        .NUMBER => colors.number,
        .STRING => colors.string,

        // Identifiers
        .IDENTIFIER => colors.identifier,

        // Operators
        .ASSIGNMENT,
        .EQUALS,
        .NOT_EQUALS,
        .NOT,
        .LESS,
        .LESS_EQUALS,
        .GREATER,
        .GREATER_EQUALS,
        .AND,
        .OR,
        .BITWISE_AND,
        .BITWISE_OR,
        .BITWISE_XOR,
        .PLUS,
        .MINUS,
        .STAR,
        .SLASH,
        .STAR_STAR,
        .PERCENT,
        .PLUS_EQUALS,
        .MINUS_EQUALS,
        .STAR_EQUALS,
        .SLASH_EQUALS,
        .PERCENT_EQUALS,
        .PLUS_PLUS,
        .MINUS_MINUS,
        .ARROW,
        => colors.operator,

        // Punctuation
        .DOT,
        .DOT_DOT,
        .SEMI_COLON,
        .COLON,
        .QUESTION,
        .COMMA,
        .OPEN_PAREN,
        .CLOSE_PAREN,
        .OPEN_BRACKET,
        .CLOSE_BRACKET,
        .OPEN_CURLY,
        .CLOSE_CURLY,
        => colors.punctuation,

        // MISC (enforces exhaustive switching)
        .EOF => colors.identifier,
    };
}

pub fn highlight(allocator: std.mem.Allocator, source: []const u8) !void {
    const tokenize = @import("../lexer/tokenizer.zig").tokenize;
    const tokens = try tokenize(allocator, source);
    const writer_out = driver.getWriterOut();

    var i: usize = 0;
    var last: usize = 0;

    while (i < tokens.items.len) : (i += 1) {
        const tok = tokens.items[i];
        if (tok.kind == .EOF) break;

        // Print skipped characters between tokens
        if (tok.start > last) {
            try writer_out.writeAll(source[last..tok.start]);
        }

        // Lookahead to check if identifier part of a function call
        const is_function_call = tok.kind == .IDENTIFIER and
            (i + 1 < tokens.items.len and tokens.items[i + 1].kind == .OPEN_PAREN);

        const color = if (is_function_call) colors.function else colorForKind(tok.kind);

        try writer_out.print("{s}{s}{s}", .{
            color,
            source[tok.start..tok.end],
            colors.reset,
        });

        last = tok.end;
    }

    // Print any remaining trailing source
    if (last < source.len) {
        try writer_out.writeAll(source[last..]);
    }
}
