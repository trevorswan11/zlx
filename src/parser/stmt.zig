const std = @import("std");

const parser = @import("parser.zig");
const token = @import("../lexer/token.zig");
const ast = @import("ast.zig");
const lus = @import("lookups.zig");
const expr = @import("expr.zig");
const types = @import("types.zig");

const BindingPower = lus.BindingPower;
const binding = lus.binding;

pub fn parseStmt(p: *parser.Parser) !ast.Stmt {
    if (lus.stmt_lu.get(p.currentTokenKind())) |stmt_fn| {
        return try stmt_fn(p);
    } else {
        return try parseExpressionStmt(p);
    }
}

pub fn parseExpressionStmt(p: *parser.Parser) !ast.Stmt {
    const expression = try expr.parseExpr(p, binding.DEFAULT_BP);
    if (!p.repl) {
        _ = try p.expect(.SEMI_COLON);
    } else {
        _ = p.advance();
    }

    return .{
        .expression = .{
            .expression = try ast.boxExpr(p, expression),
        },
    };
}

pub fn parseBlockStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.OPEN_CURLY);
    var body = try std.ArrayList(*ast.Stmt).initCapacity(p.allocator, p.numTokens());

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_CURLY) {
        const stmt = try parseStmt(p);
        const stmt_ptr = try ast.boxStmt(p, stmt);
        try body.append(stmt_ptr);
    }

    _ = try p.expect(.CLOSE_CURLY);
    return .{
        .block = .{
            .body = body,
        },
    };
}

pub fn parseVarDeclStmt(p: *parser.Parser) !ast.Stmt {
    const stderr = std.io.getStdErr().writer();
    var explicit_type: ?ast.Type = null;
    const start_token = p.advance().kind;
    const is_constant = start_token == .CONST;
    const symbol_name = try p.expectError(.IDENTIFIER, error.VarDeclStmt);

    var reserved_map = try token.Token.getReservedMap(p.allocator);
    defer reserved_map.deinit();
    if (reserved_map.get(symbol_name.value) != null) {
        try stderr.print("Reserved Identifier \"{s}\" used for variable declaration @ Line {d}\n", .{
            symbol_name.value,
            p.tokens.items[p.pos].line,
        });
        return error.ReservedIdentifier;
    }

    if (p.currentTokenKind() == .COLON) {
        _ = try p.expect(.COLON);
        explicit_type = try types.parseType(p, binding.DEFAULT_BP);
    }

    var assignment_value: ?ast.Expr = null;
    if (p.currentTokenKind() != .SEMI_COLON) {
        _ = try p.expect(.ASSIGNMENT);
        assignment_value = try expr.parseExpr(p, binding.ASSIGNMENT);
    } else if (explicit_type == null) {
        try stderr.print("Missing explicit type for variable declaration at token {d}/{d} @ Line {d}\n", .{
            p.pos,
            p.tokens.items.len,
            p.tokens.items[p.pos].line,
        });
        try p.currentToken().debugRuntime();
        return error.ExplicitVarDeclParse;
    }

    if (!p.repl) {
        _ = try p.expect(.SEMI_COLON);
    } else {
        _ = p.advance();
    }

    if (is_constant and assignment_value == null) {
        try stderr.print("Cannot define constant variable without providing default value at token {d}/{d} @ Line {d}\n", .{
            p.pos,
            p.tokens.items.len,
            p.tokens.items[p.pos].line,
        });
        try p.currentToken().debugRuntime();
        return error.VarDeclParse;
    }

    var av_ptr: ?*ast.Expr = null;
    if (assignment_value) |av| {
        av_ptr = try ast.boxExpr(p, av);
    }

    var et_ptr: ?*ast.Type = null;
    if (explicit_type) |et| {
        et_ptr = try ast.boxType(p, et);
    }

    return .{
        .var_decl = .{
            .constant = is_constant,
            .identifier = symbol_name.value,
            .assigned_value = av_ptr,
            .explicit_type = et_ptr,
        },
    };
}

pub const FunctionInfo = struct {
    parameters: std.ArrayList(*ast.Parameter),
    return_type: *ast.Type,
    body: std.ArrayList(*ast.Stmt),
};

pub fn parseFnParamsAndBody(p: *parser.Parser) !FunctionInfo {
    _ = try p.expect(.OPEN_PAREN);
    const stderr = std.io.getStdErr().writer();
    var function_params = std.ArrayList(*ast.Parameter).init(p.allocator);
    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_PAREN) {
        const expected = try p.expect(.IDENTIFIER);
        const param_name = expected.value;

        var reserved_map = try token.Token.getReservedMap(p.allocator);
        defer reserved_map.deinit();
        if (reserved_map.get(param_name) != null) {
            try stderr.print("Reserved Identifier \"{s}\" used for function parameter @ Line {d}\n", .{
                param_name,
                p.tokens.items[p.pos].line,
            });
            return error.ReservedIdentifier;
        }

        var param_type: ast.Type = .{
            .symbol = .{
                .value_type = "any",
            },
        };

        if (p.currentTokenKind() == .COLON) {
            _ = try p.expect(.COLON);
            param_type = try types.parseType(p, binding.DEFAULT_BP);
        }

        const param_ptr = try p.allocator.create(ast.Parameter);
        const param = ast.Parameter{
            .name = param_name,
            .type = try ast.boxType(p, param_type),
        };
        param_ptr.* = param;
        try function_params.append(param_ptr);

        if (!p.currentToken().isOneOfManyRuntime(&[_]token.TokenKind{ .CLOSE_PAREN, .EOF })) {
            _ = try p.expect(.COMMA);
        }
    }

    _ = try p.expect(.CLOSE_PAREN);
    var return_type: ast.Type = undefined;

    if (p.currentTokenKind() == .COLON) {
        _ = p.advance();
        return_type = try types.parseType(p, binding.DEFAULT_BP);
    } else {
        return_type = .{
            .symbol = .{
                .value_type = "void",
            },
        };
    }

    const block_stmt = try parseBlockStmt(p);
    const function_body = block_stmt.block.body;
    return FunctionInfo{
        .body = function_body,
        .parameters = function_params,
        .return_type = try ast.boxType(p, return_type),
    };
}

pub fn parseFnDeclaration(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.FN);
    const function_name = (try p.expect(.IDENTIFIER)).value;
    const func_info = try parseFnParamsAndBody(p);

    return .{
        .function_decl = .{
            .parameters = func_info.parameters,
            .return_type = func_info.return_type,
            .body = func_info.body,
            .name = function_name,
        },
    };
}

pub fn parseIfStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.IF);
    const condition = try expr.parseExpr(p, binding.ASSIGNMENT);
    const consequent = try parseBlockStmt(p);

    var alternate: ?ast.Stmt = null;
    if (p.currentTokenKind() == .ELSE) {
        _ = try p.expect(.ELSE);

        if (p.currentTokenKind() == .IF) {
            alternate = try parseIfStmt(p);
        } else {
            alternate = try parseBlockStmt(p);
        }
    }

    const cons_ptr = try ast.boxStmt(p, consequent);
    var alt_ptr: ?*ast.Stmt = null;
    if (alternate) |a| {
        alt_ptr = try ast.boxStmt(p, a);
    }
    const cond_ptr = try ast.boxExpr(p, condition);

    return .{
        .if_stmt = .{
            .condition = cond_ptr,
            .consequent = cons_ptr,
            .alternate = alt_ptr,
        },
    };
}

pub fn parseImportStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.IMPORT);
    const stderr = std.io.getStdErr().writer();
    var import_from: []const u8 = undefined;
    const import_type = try p.expectMany(&[_]token.TokenKind{ .IDENTIFIER, .STAR });
    const import_name = import_type.value;

    var reserved_map = try token.Token.getReservedMap(p.allocator);
    defer reserved_map.deinit();

    const builtin_mods = @import("../builtins/builtins.zig").builtin_modules;
    var is_builtin = false;
    for (builtin_mods) |mod| {
        if (std.mem.eql(u8, import_name, mod.name)) {
            is_builtin = true;
        }
    }

    if (!is_builtin and reserved_map.get(import_name) != null) {
        try stderr.print("Reserved Identifier \"{s}\" used for non-builtin import @ Line {d}\n", .{
            import_name,
            p.tokens.items[p.pos].line,
        });
        return error.ReservedIdentifier;
    }

    if (p.currentTokenKind() == .FROM) {
        _ = try p.expect(.FROM);
        import_from = (try p.expect(.STRING)).value;
    } else {
        if (std.mem.eql(u8, import_name, "*")) {
            return error.MissingWildcardFile;
        }
        import_from = import_name;
    }

    if (!p.repl) {
        _ = try p.expect(.SEMI_COLON);
    } else {
        _ = p.advance();
    }
    return .{
        .import_stmt = .{
            .name = import_name,
            .from = import_from,
        },
    };
}

pub fn parseForEachStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.FOREACH);
    const value_name = (try p.expect(.IDENTIFIER)).value;

    var index: bool = false;
    var index_name: ?[]const u8 = null;
    if (p.currentTokenKind() == .COMMA) {
        _ = try p.expect(.COMMA);
        index_name = (try p.expect(.IDENTIFIER)).value;
        index = true;
    }

    _ = try p.expect(.IN);
    const iterable = try expr.parseExpr(p, binding.DEFAULT_BP);
    const block_stmt = try parseBlockStmt(p);
    const body = block_stmt.block.body;

    return .{
        .foreach_stmt = .{
            .value = value_name,
            .index = index,
            .index_name = index_name,
            .iterable = try ast.boxExpr(p, iterable),
            .body = body,
        },
    };
}

pub fn parseWhileStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.WHILE);
    const condition = try expr.parseExpr(p, binding.DEFAULT_BP);
    const block_stmt = try parseBlockStmt(p);

    return .{
        .while_stmt = .{
            .condition = try ast.boxExpr(p, condition),
            .body = block_stmt.block.body,
        },
    };
}

pub fn parseClassDeclStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.CLASS);
    const stderr = std.io.getStdErr().writer();
    const class_name = (try p.expect(.IDENTIFIER)).value;
    var reserved_map = try token.Token.getReservedMap(p.allocator);
    defer reserved_map.deinit();
    if (reserved_map.get(class_name) != null) {
        try stderr.print("Reserved Identifier \"{s}\" used for class name @ Line {d}\n", .{
            class_name,
            p.tokens.items[p.pos].line,
        });
        return error.ReservedIdentifier;
    }
    const class_body = try parseBlockStmt(p);

    return .{
        .class_decl = .{
            .name = class_name,
            .body = class_body.block.body,
        },
    };
}

pub fn parseBreakStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.BREAK);
    _ = try p.expect(.SEMI_COLON);

    return .{
        .break_stmt = .{},
    };
}

pub fn parseContinueStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.CONTINUE);
    _ = try p.expect(.SEMI_COLON);

    return .{
        .continue_stmt = .{},
    };
}

pub fn parseReturnStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.RETURN);

    if (p.currentTokenKind() == .SEMI_COLON) {
        _ = try p.expect(.SEMI_COLON);
        return .{
            .return_stmt = .{
                .value = null,
            },
        };
    }

    const value_expr = try ast.boxExpr(p, try expr.parseExpr(p, binding.DEFAULT_BP));
    _ = try p.expect(.SEMI_COLON);
    return .{
        .return_stmt = .{
            .value = value_expr,
        },
    };
}

pub fn parseMatchStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.MATCH);
    const exp = try ast.boxExpr(p, try expr.parseExpr(p, binding.DEFAULT_BP));
    _ = try p.expect(.OPEN_CURLY);

    var cases = std.ArrayList(ast.MatchCase).init(p.allocator);

    while (p.currentTokenKind() != .CLOSE_CURLY) {
        const pattern_expr = try ast.boxExpr(p, try expr.parseExpr(p, binding.DEFAULT_BP));
        _ = try p.expect(.ARROW);

        var stmt: *ast.Stmt = undefined;

        if (p.currentTokenKind() == .OPEN_CURLY) {
            // Parse block statement and require a trailing comma
            stmt = try ast.boxStmt(p, try parseBlockStmt(p));
            _ = try p.expect(.COMMA);
        } else {
            // Parse single statement and require trailing semicolon (consumed while parsing)
            stmt = try ast.boxStmt(p, try parseStmt(p));
        }

        try cases.append(.{
            .pattern = pattern_expr,
            .body = stmt,
        });
    }

    _ = try p.expect(.CLOSE_CURLY);

    return .{
        .match_stmt = .{
            .expression = exp,
            .cases = cases,
        },
    };
}
