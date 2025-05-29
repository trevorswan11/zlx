const std = @import("std");

const parser = @import("parser.zig");
const token = @import("../lexer/token.zig");
const ast = @import("../ast/ast.zig");
const lus = @import("lookups.zig");
const expr = @import("expr.zig");
const types = @import("types.zig");

pub fn parseStmt(p: *parser.Parser) !ast.Stmt {
    if (lus.stmt_lu.get(p.currentTokenKind())) |stmt_fn| {
        return try stmt_fn(p);
    } else {
        return try parseExpressionStmt(p);
    }
}

pub fn parseExpressionStmt(p: *parser.Parser) !ast.Stmt {
    const expression = try expr.parseExpr(p, .DEFAULT_BP);
    _ = try p.expect(.SEMI_COLON);

    return ast.Stmt{
        .expression = ast.ExpressionStmt{
            .expression = expression,
        },
    };
}

pub fn parseBlockStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.OPEN_CURLY);
    var body = try std.ArrayList(*ast.Stmt).initCapacity(p.allocator, p.numTokens());

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_CURLY) {
        try body.append(@constCast(&(try parseStmt(p))));
    }

    _ = try p.expect(.CLOSE_CURLY);
    return ast.Stmt{
        .block = ast.BlockStmt{
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

    if (p.currentTokenKind() == .COLON) {
        _ = try p.expect(.COLON);
        explicit_type = try types.parseType(p, .DEFAULT_BP);
    }

    var assignment_value: ?ast.Expr = undefined;
    if (p.currentTokenKind() != .SEMI_COLON) {
        _ = try p.expect(.ASSIGNMENT);
        assignment_value = try expr.parseExpr(p, .ASSIGNMENT);
    } else if (explicit_type == null) {
        try stderr.print("Missing explicit type for variable declaration at token {d}/{d}\n", .{
            p.pos,
            p.tokens.items.len,
        });
        try p.currentToken().debugRuntime();
        return error.ExplicitVarDeclParse;
    }

    _ = try p.expect(.SEMI_COLON);

    if (is_constant and assignment_value == null) {
        try stderr.print("Cannot define constant variable without providing default value at token {d}/{d}\n", .{
            p.pos,
            p.tokens.items.len,
        });
        try p.currentToken().debugRuntime();
        return error.VarDeclParse;
    }

    return ast.Stmt{
        .var_decl = ast.VarDeclarationStmt{
            .constant = is_constant,
            .identifier = symbol_name.value,
            .assigned_value = assignment_value,
            .explicit_type = explicit_type,
        },
    };
}

pub const FunctionInfo = struct {
    parameters: std.ArrayList(ast.Parameter),
    return_type: ast.Type,
    body: std.ArrayList(*ast.Stmt),
};

pub fn parseFnParamsAndBody(p: *parser.Parser) !FunctionInfo {
    var function_params = std.ArrayList(ast.Parameter).init(p.allocator);
    _ = try p.expect(.OPEN_PAREN);
    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_PAREN) {
        const expected = try p.expect(.IDENTIFIER);
        const param_name = expected.value;
        _ = try p.expect(.COLON);
        const param_type = try types.parseType(p, .DEFAULT_BP);

        try function_params.append(ast.Parameter{
            .name = param_name,
            .type = param_type,
        });

        if (!@constCast(&p.currentToken()).isOneOfMany(@constCast(&[_]token.TokenKind{ .CLOSE_PAREN, .EOF }))) {
            _ = try p.expect(.COMMA);
        }
    }

    _ = try p.expect(.CLOSE_PAREN);
    var return_type: ast.Type = undefined;

    if (p.currentTokenKind() == .COLON) {
        _ = p.advance();
        return_type = try types.parseType(p, .DEFAULT_BP);
    }

    const block_stmt = try parseBlockStmt(p);
    const function_body = block_stmt.block.body;
    return FunctionInfo{
        .body = function_body,
        .parameters = function_params,
        .return_type = return_type,
    };
}

pub fn parseFnDeclaration(p: *parser.Parser) !ast.Stmt {
    _ = p.advance();
    const function_name = (try p.expect(.IDENTIFIER)).value;
    const func_info = try parseFnParamsAndBody(p);

    return ast.Stmt{
        .function_decl = ast.FunctionDeclarationStmt{
            .parameters = func_info.parameters,
            .return_type = func_info.return_type,
            .body = func_info.body,
            .name = function_name,
        },
    };
}

pub fn parseIfStmt(p: *parser.Parser) !ast.Stmt {
    _ = p.advance();
    const condition = try expr.parseExpr(p, .ASSIGNMENT);
    const consequent = try parseBlockStmt(p);

    var alternate: ast.Stmt = undefined;
    if (p.currentTokenKind() == .ELSE) {
        _ = p.advance();

        if (p.currentTokenKind() == .IF) {
            alternate = try parseIfStmt(p);
        } else {
            alternate = try parseBlockStmt(p);
        }
    }

    return ast.Stmt{
        .if_stmt = ast.IfStmt{
            .alternate = @constCast(&alternate),
            .condition = condition,
            .consequent = @constCast(&consequent),
        },
    };
}

pub fn parseImportStmt(p: *parser.Parser) !ast.Stmt {
    _ = p.advance();
    var import_from: []const u8 = undefined;
    const import_name = (try p.expect(.IDENTIFIER)).value;

    if (p.currentTokenKind() == .FROM) {
        _ = p.advance();
        import_from = (try p.expect(.STRING)).value;
    } else {
        import_from = import_name;
    }

    _ = try p.expect(.SEMI_COLON);
    return ast.Stmt{
        .import_stmt = ast.ImportStmt{
            .name = import_name,
            .from = import_from,
        },
    };
}

pub fn parseForEachStmt(p: *parser.Parser) !ast.Stmt {
    _ = p.advance();
    const value_name = (try p.expect(.IDENTIFIER)).value;

    var index: bool = undefined;
    if (p.currentTokenKind() == .COMMA) {
        _ = try p.expect(.COMMA);
        _ = try p.expect(.IDENTIFIER);
        index = true;
    }

    _ = try p.expect(.IN);
    const iterable = try expr.parseExpr(p, .DEFAULT_BP);
    const block_stmt = try parseBlockStmt(p);
    const body = block_stmt.block.body;

    return ast.Stmt{
        .foreach_stmt = ast.ForeachStmt{
            .value = value_name,
            .index = index,
            .iterable = iterable,
            .body = body,
        },
    };
}

pub fn parseClassDeclStmt(p: *parser.Parser) !ast.Stmt {
    _ = p.advance();
    const class_name = (try p.expect(.IDENTIFIER)).value;
    const class_body = try parseBlockStmt(p);

    return ast.Stmt{
        .class_decl = ast.ClassDeclarationStmt{
            .name = class_name,
            .body = class_body.block.body,
        },
    };
}
