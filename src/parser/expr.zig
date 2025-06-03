const std = @import("std");

const parser = @import("parser.zig");
const token = @import("../lexer/token.zig");
const ast = @import("ast.zig");
const lus = @import("lookups.zig");
const stmts = @import("stmt.zig");

fn boxExpr(p: *parser.Parser, e: ast.Expr) !*ast.Expr {
    const ptr = try p.allocator.create(ast.Expr);
    ptr.* = e;
    return ptr;
}

fn boxType(p: *parser.Parser, e: ast.Type) !*ast.Type {
    const ptr = try p.allocator.create(ast.Type);
    ptr.* = e;
    return ptr;
}

pub fn parseExpr(p: *parser.Parser, bp: lus.BindingPower) !ast.Expr {
    const stderr = std.io.getStdErr().writer();
    var token_kind = p.currentTokenKind();

    if (lus.nud_lu.get(token_kind)) |nud_fn| {
        var left = try nud_fn(p);

        while (lus.bp_lu.get(p.currentTokenKind()) != null and @intFromEnum(lus.bp_lu.get(p.currentTokenKind()).?) > @intFromEnum(bp)) {
            token_kind = p.currentTokenKind();
            if (lus.led_lu.get(token_kind)) |led_fn| {
                left = try led_fn(p, left, bp);
            } else {
                try stderr.print("Expr Parse Error: LED Handler expected for token {s} ({d}/{d}) @ Line {d}\n", .{
                    try token.tokenKindString(p.allocator, token_kind),
                    p.pos,
                    p.tokens.items.len,
                    p.tokens.items[p.pos].line,
                });
                try p.currentToken().debugRuntime();
                return error.ExpectedLEDHandler;
            }
        }

        return left;
    } else {
        try stderr.print("Expr Parse Error: NUD Handler expected for token {s} ({d}/{d}) @ Line {d}\n", .{
            try token.tokenKindString(p.allocator, token_kind),
            p.pos,
            p.tokens.items.len,
            p.tokens.items[p.pos].line,
        });
        try p.currentToken().debugRuntime();
        return error.ExpectedNUDHandler;
    }
}

pub fn parsePrefixExpr(p: *parser.Parser) !ast.Expr {
    const operator_token = p.advance();
    const expr = try parseExpr(p, .UNARY);

    return ast.Expr{
        .prefix = ast.PrefixExpr{
            .operator = operator_token,
            .right = try boxExpr(p, expr),
        },
    };
}

pub fn parseAssignmentExpr(p: *parser.Parser, left: ast.Expr, bp: lus.BindingPower) !ast.Expr {
    _ = p.advance();
    const rhs = try parseExpr(p, bp);

    return ast.Expr{
        .assignment = ast.AssignmentExpr{
            .assignee = try boxExpr(p, left),
            .assigned_value = try boxExpr(p, rhs),
        },
    };
}

pub fn parseRangeExpr(p: *parser.Parser, left: ast.Expr, bp: lus.BindingPower) !ast.Expr {
    _ = p.advance();
    const upper = try parseExpr(p, bp);

    return ast.Expr{
        .range_expr = ast.RangeExpr{
            .lower = try boxExpr(p, left),
            .upper = try boxExpr(p, upper),
        },
    };
}

pub fn parseBinaryExpr(p: *parser.Parser, left: ast.Expr, bp: lus.BindingPower) !ast.Expr {
    const stderr = std.io.getStdErr().writer();
    const operator_token = p.advance();
    const operator_bp = lus.bp_lu.get(operator_token.kind) orelse {
        try stderr.print("No binding power associated with operator: {s} at token {d}/{d} @ Line {d}\n", .{
            try token.tokenKindString(p.allocator, operator_token.kind),
            p.pos,
            p.tokens.items.len,
            p.tokens.items[p.pos].line,
        });
        try p.currentToken().debugRuntime();
        try operator_token.debugRuntime();
        return error.BinaryExprOperator;
    };
    const right = try parseExpr(p, operator_bp);
    _ = bp;

    return ast.Expr{
        .binary = ast.BinaryExpr{
            .left = try boxExpr(p, left),
            .operator = operator_token,
            .right = try boxExpr(p, right),
        },
    };
}

pub fn parsePrimaryExpr(p: *parser.Parser) !ast.Expr {
    const stderr = std.io.getStdErr().writer();
    switch (p.currentTokenKind()) {
        .NUMBER => {
            const number = try std.fmt.parseFloat(f64, p.advance().value);
            return ast.Expr{
                .number = ast.NumberExpr{
                    .value = number,
                },
            };
        },
        .STRING => {
            return ast.Expr{
                .string = ast.StringExpr{
                    .value = p.advance().value,
                },
            };
        },
        .IDENTIFIER => {
            return ast.Expr{
                .symbol = ast.SymbolExpr{
                    .value = p.advance().value,
                },
            };
        },
        else => {
            try stderr.print("Cannot create Primary Expr from {s} at token {d}/{d} @ Line {d}\n", .{
                try token.tokenKindString(p.allocator, p.currentTokenKind()),
                p.pos,
                p.tokens.items.len,
                p.tokens.items[p.pos].line,
            });
            try p.currentToken().debugRuntime();
            return error.PrimaryExprParse;
        },
    }
}

pub fn parseMemberExpr(p: *parser.Parser, left: ast.Expr, bp: lus.BindingPower) !ast.Expr {
    if (p.advance().kind == .OPEN_BRACKET) {
        const rhs = try parseExpr(p, bp);
        _ = try p.expect(.CLOSE_BRACKET);
        return ast.Expr{
            .computed = ast.ComputedExpr{
                .member = try boxExpr(p, left),
                .property = try boxExpr(p, rhs),
            },
        };
    } else {
        const rhs = try p.expect(.IDENTIFIER);
        return ast.Expr{
            .member = ast.MemberExpr{
                .member = try boxExpr(p, left),
                .property = rhs.value,
            },
        };
    }
}

pub fn parseArrayLiteralExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.OPEN_BRACKET);
    var array_contents = try std.ArrayList(*ast.Expr).initCapacity(p.allocator, p.numTokens());

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_BRACKET) {
        try array_contents.append(try boxExpr(p, try parseExpr(p, .LOGICAL)));

        if (!@constCast(&p.currentToken()).isOneOfMany(@constCast(&[_]token.TokenKind{ .EOF, .CLOSE_BRACKET }))) {
            _ = try p.expect(.COMMA);
        }
    }

    _ = try p.expect(.CLOSE_BRACKET);

    return ast.Expr{
        .array_literal = ast.ArrayLiteral{
            .contents = array_contents,
        },
    };
}

pub fn parseGroupingExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.OPEN_PAREN);
    const expr = try parseExpr(p, .DEFAULT_BP);
    _ = try p.expect(.CLOSE_PAREN);
    return expr;
}

pub fn parseCallExpr(p: *parser.Parser, left: ast.Expr, bp: lus.BindingPower) !ast.Expr {
    _ = p.advance();
    var arguments = try std.ArrayList(*ast.Expr).initCapacity(p.allocator, p.numTokens());
    _ = bp;

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_PAREN) {
        try arguments.append(try boxExpr(p, try parseExpr(p, .ASSIGNMENT)));

        if (!@constCast(&p.currentToken()).isOneOfMany(@constCast(&[_]token.TokenKind{ .EOF, .CLOSE_PAREN }))) {
            _ = try p.expect(.COMMA);
        }
    }

    _ = try p.expect(.CLOSE_PAREN);
    return ast.Expr{
        .call = ast.CallExpr{
            .method = try boxExpr(p, left),
            .arguments = arguments,
        },
    };
}

pub fn parseFnExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.FN);
    const func_info = try stmts.parseFnParamsAndBody(p);

    return ast.Expr{
        .function_expr = ast.FunctionExpr{
            .parameters = func_info.parameters,
            .return_type = func_info.return_type,
            .body = func_info.body,
        },
    };
}

pub fn parseObjectLiteral(p: *parser.Parser) !ast.Expr {
    _ = p.advance();
    var entries = std.ArrayList(*ast.ObjectEntry).init(p.allocator);

    while (p.currentTokenKind() != .CLOSE_CURLY) {
        const key_token = try p.expect(.IDENTIFIER);
        _ = try p.expect(.COLON);
        const value_expr = try parseExpr(p, .DEFAULT_BP);

        const obj_ptr = try p.allocator.create(ast.ObjectEntry);
        obj_ptr.* = ast.ObjectEntry{
            .key = key_token.value,
            .value = try boxExpr(p, value_expr),
        };

        try entries.append(obj_ptr);

        if (p.match(.COMMA) or p.match(.SEMI_COLON)) {
            _ = p.advance();
        } else if (p.currentTokenKind() != .CLOSE_CURLY) {
            return error.ExpectedCommaOrCloseCurly;
        }
    }

    _ = try p.expect(.CLOSE_CURLY);
    return ast.Expr{
        .object = ast.ObjectExpr{
            .entries = entries,
        },
    };
}
