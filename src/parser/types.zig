const std = @import("std");
const token = @import("../lexer/token.zig");
const ast = @import("ast.zig");
const lus = @import("lookups.zig");
const parser = @import("parser.zig");
const driver = @import("../utils/driver.zig");

const TokenKind = token.TokenKind;
const Parser = parser.Parser;
const BindingPower = lus.BindingPower;
const binding = lus.binding;

// === Function Types ===
const TypeNudHandler = *const fn (*Parser) anyerror!ast.Type;
const TypeLedHandler = *const fn (*Parser, ast.Type, BindingPower) anyerror!ast.Type;

// === Lookup Tables ===
var type_bp_lu: std.AutoHashMap(TokenKind, BindingPower) = undefined;
var type_nud_lu: std.AutoHashMap(TokenKind, TypeNudHandler) = undefined;
var type_led_lu: std.AutoHashMap(TokenKind, TypeLedHandler) = undefined;

// === Registration ===
pub fn typeLed(kind: TokenKind, bp: BindingPower, led_fn: TypeLedHandler) !void {
    _ = try type_bp_lu.put(kind, bp);
    _ = try type_led_lu.put(kind, led_fn);
}

pub fn typeNud(kind: TokenKind, _: BindingPower, nud_fn: TypeNudHandler) !void {
    _ = try type_bp_lu.put(kind, binding.PRIMARY);
    _ = try type_nud_lu.put(kind, nud_fn);
}

// === Token Lookup Setup ===
pub fn createTypeTokenLookups(allocator: std.mem.Allocator) !void {
    type_bp_lu = std.AutoHashMap(TokenKind, BindingPower).init(allocator);
    type_nud_lu = std.AutoHashMap(TokenKind, TypeNudHandler).init(allocator);
    type_led_lu = std.AutoHashMap(TokenKind, TypeLedHandler).init(allocator);

    // IDENTIFIER => SymbolType
    try typeNud(.IDENTIFIER, binding.PRIMARY, struct {
        pub fn afn(p: *Parser) !ast.Type {
            return .{
                .symbol = .{
                    .value_type = p.advance().value,
                },
            };
        }
    }.afn);

    // []number => ListType
    try typeNud(.OPEN_BRACKET, binding.MEMBER, struct {
        pub fn afn(p: *Parser) !ast.Type {
            _ = p.advance();
            _ = try p.expect(.CLOSE_BRACKET);
            const inner_val = try parseType(p, binding.DEFAULT_BP);
            const inner_ptr = try p.allocator.create(ast.Type);
            inner_ptr.* = inner_val;

            return .{
                .list = .{
                    .underlying = inner_ptr,
                },
            };
        }
    }.afn);
}

// === Type Parser ===
pub fn parseType(p: *Parser, bp: BindingPower) !ast.Type {
    const token_kind = p.currentTokenKind();
    const writer_err = driver.getWriterErr();

    const nud_fn = type_nud_lu.get(token_kind) orelse {
        try writer_err.print("Type Parse Error: NUD Handler expected for token {s} ({d}/{d})\n", .{
            try token.tokenKindString(p.allocator, token_kind),
            p.pos,
            p.tokens.items.len,
        });
        return error.ExpectedNUDHandler;
    };
    var left = try nud_fn(p);

    while ((type_bp_lu.get(p.currentTokenKind()) orelse binding.DEFAULT_BP).left > bp.right) {
        const next_kind = p.currentTokenKind();

        const led_fn = type_led_lu.get(next_kind) orelse {
            try writer_err.print("Type Parse Error: LED Handler expected for token {s} ({d}/{d})\n", .{
                try token.tokenKindString(p.allocator, next_kind),
                p.pos,
                p.tokens.items.len,
            });
            return error.ExpectedLEDHandler;
        };
        left = try led_fn(p, left, bp);
    }

    return left;
}
