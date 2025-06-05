const std = @import("std");

const parser = @import("parser.zig");
const token = @import("../lexer/token.zig");
const ast = @import("ast.zig");
const lus = @import("lookups.zig");
const stmts = @import("stmt.zig");

const BindingPower = lus.BindingPower;
const binding = lus.binding;

pub fn parseExpr(p: *parser.Parser, min_bp: BindingPower) !ast.Expr {
    const stderr = std.io.getStdErr().writer();
    var token_kind = p.currentTokenKind();

    if (lus.nud_lu.get(token_kind)) |nud_fn| {
        var left = try nud_fn(p);

        while (true) {
            token_kind = p.currentTokenKind();

            // stop at EOF or anything without a known binding power
            const next_bp = lus.bp_lu.get(token_kind) orelse break;
            if (next_bp.left < min_bp.right) break;

            const led_fn = lus.led_lu.get(token_kind) orelse {
                try stderr.print("Expr Parse Error: LED Handler expected for token {s} ({d}/{d}) @ Line {d}\n", .{
                    try token.tokenKindString(p.allocator, token_kind),
                    p.pos,
                    p.tokens.items.len,
                    p.tokens.items[p.pos].line,
                });
                try p.currentToken().debugRuntime();
                return error.ExpectedLEDHandler;
            };

            left = try led_fn(p, left, next_bp);
        }

        return left;
    } else {
        try stderr.print("Expr Parse Error: NUD Handler expected for token {s} ({d}/{d}) @ Line {d}\n", .{
            try token.tokenKindString(p.allocator, token_kind),
            p.pos,
            p.tokens.items.len,
            p.tokens.items[p.pos].line,
        });
        return error.ExpectedNUDHandler;
    }
}

pub fn parsePrefixExpr(p: *parser.Parser) !ast.Expr {
    const operator_token = p.advance();
    const expr = try parseExpr(p, binding.UNARY);

    return .{
        .prefix = .{
            .operator = operator_token,
            .right = try ast.boxExpr(p, expr),
        },
    };
}

pub fn parseAssignmentExpr(p: *parser.Parser, left: ast.Expr, bp: BindingPower) !ast.Expr {
    _ = p.advance();
    const rhs = try parseExpr(p, bp);

    return .{
        .assignment = .{
            .assignee = try ast.boxExpr(p, left),
            .assigned_value = try ast.boxExpr(p, rhs),
        },
    };
}

pub fn parseRangeExpr(p: *parser.Parser, left: ast.Expr, bp: BindingPower) !ast.Expr {
    _ = p.advance();
    const upper = try parseExpr(p, bp);

    return .{
        .range_expr = .{
            .lower = try ast.boxExpr(p, left),
            .upper = try ast.boxExpr(p, upper),
        },
    };
}

pub fn parseBinaryExpr(p: *parser.Parser, left: ast.Expr, bp: BindingPower) !ast.Expr {
    const operator_token = p.advance();
    const right = try parseExpr(p, .{
        .left = 0,
        .right = bp.right,
    });

    return .{
        .binary = .{
            .left = try ast.boxExpr(p, left),
            .operator = operator_token,
            .right = try ast.boxExpr(p, right),
        },
    };
}

pub fn parsePrimaryExpr(p: *parser.Parser) !ast.Expr {
    const stderr = std.io.getStdErr().writer();
    switch (p.currentTokenKind()) {
        .NUMBER => {
            const number = try std.fmt.parseFloat(f64, p.advance().value);
            return .{
                .number = .{
                    .value = number,
                },
            };
        },
        .STRING => {
            return .{
                .string = .{
                    .value = p.advance().value,
                },
            };
        },
        .IDENTIFIER => {
            return .{
                .symbol = .{
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

pub fn parseMemberExpr(p: *parser.Parser, left: ast.Expr, bp: BindingPower) !ast.Expr {
    if (p.advance().kind == .OPEN_BRACKET) {
        const rhs = try parseExpr(p, bp);
        _ = try p.expect(.CLOSE_BRACKET);
        return .{
            .computed = .{
                .member = try ast.boxExpr(p, left),
                .property = try ast.boxExpr(p, rhs),
            },
        };
    } else {
        const rhs = try p.expect(.IDENTIFIER);
        return .{
            .member = .{
                .member = try ast.boxExpr(p, left),
                .property = rhs.value,
            },
        };
    }
}

pub fn parseArrayLiteralExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.OPEN_BRACKET);
    var array_contents = try std.ArrayList(*ast.Expr).initCapacity(p.allocator, p.numTokens());

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_BRACKET) {
        try array_contents.append(try ast.boxExpr(p, try parseExpr(p, binding.LOGICAL)));

        if (!p.currentToken().isOneOfManyRuntime(&[_]token.TokenKind{ .EOF, .CLOSE_BRACKET })) {
            _ = try p.expect(.COMMA);
        }
    }

    _ = try p.expect(.CLOSE_BRACKET);

    return .{
        .array_literal = .{
            .contents = array_contents,
        },
    };
}

pub fn parseGroupingExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.OPEN_PAREN);
    const expr = try parseExpr(p, binding.DEFAULT_BP);
    _ = try p.expect(.CLOSE_PAREN);
    return expr;
}

pub fn parseCallExpr(p: *parser.Parser, left: ast.Expr, bp: BindingPower) !ast.Expr {
    _ = p.advance();
    var arguments = try std.ArrayList(*ast.Expr).initCapacity(p.allocator, p.numTokens());
    _ = bp;

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_PAREN) {
        try arguments.append(try ast.boxExpr(p, try parseExpr(p, binding.ASSIGNMENT)));

        if (!p.currentToken().isOneOfManyRuntime(&[_]token.TokenKind{ .EOF, .CLOSE_PAREN })) {
            _ = try p.expect(.COMMA);
        }
    }

    _ = try p.expect(.CLOSE_PAREN);
    return .{
        .call = .{
            .method = try ast.boxExpr(p, left),
            .arguments = arguments,
        },
    };
}

pub fn parseFnExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.FN);
    const func_info = try stmts.parseFnParamsAndBody(p);

    return .{
        .function_expr = .{
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
        const value_expr = try parseExpr(p, binding.DEFAULT_BP);

        const obj_ptr = try p.allocator.create(ast.ObjectEntry);
        obj_ptr.* = .{
            .key = key_token.value,
            .value = try ast.boxExpr(p, value_expr),
        };

        try entries.append(obj_ptr);

        if (p.match(.COMMA) or p.match(.SEMI_COLON)) {
            _ = p.advance();
        } else if (p.currentTokenKind() != .CLOSE_CURLY) {
            return error.ExpectedCommaOrCloseCurly;
        }
    }

    _ = try p.expect(.CLOSE_CURLY);
    return .{
        .object = .{
            .entries = entries,
        },
    };
}

pub fn parseBooleanLiteral(p: *parser.Parser) !ast.Expr {
    const tok = p.advance();
    return .{
        .boolean = tok.kind == .TRUE,
    };
}

pub fn parseMatchExpr(p: *parser.Parser) !ast.Expr {
    _ = try p.expect(.MATCH);
    const expr = try ast.boxExpr(p, try parseExpr(p, binding.DEFAULT_BP));
    _ = try p.expect(.OPEN_CURLY);

    var cases = std.ArrayList(ast.MatchCase).init(p.allocator);

    while (p.currentTokenKind() != .CLOSE_CURLY) {
        const pattern = try ast.boxExpr(p, try parseExpr(p, binding.DEFAULT_BP));
        _ = try p.expect(.ARROW);

        const value_expr = try ast.boxExpr(p, try parseExpr(p, binding.DEFAULT_BP));

        if (p.currentTokenKind() == .COMMA) {
            _ = try p.expect(.COMMA);
        } else if (p.currentTokenKind() != .CLOSE_CURLY) {
            return error.ExpectedCommaOrCloseCurly;
        }

        try cases.append(ast.MatchCase{
            .pattern = pattern,
            .body = try ast.boxStmt(p, .{
                .expression = .{
                    .expression = value_expr,
                },
            }),
        });
    }

    _ = try p.expect(.CLOSE_CURLY);

    return .{
        .match_expr = .{
            .expression = expr,
            .cases = cases,
        },
    };
}
