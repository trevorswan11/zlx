const std = @import("std");
const token = @import("../lexer/token.zig");
const ast = @import("../ast/ast.zig");
const BindingPower = @import("lookups.zig").BindingPower;

const TokenKind = token.TokenKind;
const Parser = @import("parser.zig").Parser;

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

pub fn typeNud(kind: TokenKind, bp: BindingPower, nud_fn: TypeNudHandler) !void {
    _ = bp;
    _ = try type_bp_lu.put(kind, .PRIMARY);
    _ = try type_nud_lu.put(kind, nud_fn);
}

// === Token Lookup Setup ===
pub fn createTypeTokenLookups(allocator: std.mem.Allocator) !void {
    type_bp_lu = std.AutoHashMap(TokenKind, BindingPower).init(allocator);
    type_nud_lu = std.AutoHashMap(TokenKind, TypeNudHandler).init(allocator);
    type_led_lu = std.AutoHashMap(TokenKind, TypeLedHandler).init(allocator);

    // IDENTIFIER => SymbolType
    try typeNud(.IDENTIFIER, .PRIMARY, struct {
        pub fn afn(p: *Parser) !ast.Type {
            return ast.Type{
                .symbol = ast.SymbolType{
                    .value = p.advance().value,
                },
            };
        }
    }.afn);

    // []number => ListType
    try typeNud(.OPEN_BRACKET, .MEMBER, struct {
        pub fn afn(p: *Parser) !ast.Type {
            _ = p.advance();
            _ = try p.expect(.CLOSE_BRACKET);
            const inner = try parseType(p, .DEFAULT_BP);
            return ast.Type{
                .list = ast.ListType{
                    .underlying = @constCast(&inner),
                },
            };
        }
    }.afn);
}

// === Type Parser ===
pub fn parseType(p: *Parser, bp: BindingPower) !ast.Type {
    const token_kind = p.currentTokenKind();

    const nud_fn = type_nud_lu.get(token_kind) orelse
        @panic(std.fmt.allocPrintZ(std.heap.page_allocator, "type: NUD Handler expected for token {s}\n", .{try token.tokenKindString(token_kind)}) catch unreachable);

    var left = try nud_fn(p);

    while (@intFromEnum(type_bp_lu.get(p.currentTokenKind()) orelse .DEFAULT_BP) > @intFromEnum(bp)) {
        const next_kind = p.currentTokenKind();

        const led_fn = type_led_lu.get(next_kind) orelse
            @panic(std.fmt.allocPrintZ(std.heap.page_allocator, "type: LED Handler expected for token {s}\n", .{try token.tokenKindString(next_kind)}) catch unreachable);

        left = try led_fn(p, left, bp);
    }

    return left;
}
