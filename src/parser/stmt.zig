const std = @import("std");

const parser = @import("parser.zig");
const token = @import("../lexer/token.zig");
const ast = @import("ast.zig");
const lus = @import("lookups.zig");
const expr = @import("expr.zig");
const types = @import("types.zig");

const BindingPower = lus.BindingPower;
const binding = lus.binding;

fn boxStmt(p: *parser.Parser, stmt: ast.Stmt) !*ast.Stmt {
    const ptr = try p.allocator.create(ast.Stmt);
    ptr.* = stmt;
    return ptr;
}

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

pub fn parseStmt(p: *parser.Parser) !ast.Stmt {
    if (lus.stmt_lu.get(p.currentTokenKind())) |stmt_fn| {
        return try stmt_fn(p);
    } else {
        return try parseExpressionStmt(p);
    }
}

pub fn parseExpressionStmt(p: *parser.Parser) !ast.Stmt {
    const expression = try expr.parseExpr(p, binding.DEFAULT_BP);
    _ = try p.expect(.SEMI_COLON);

    return ast.Stmt{
        .expression = ast.ExpressionStmt{
            .expression = try boxExpr(p, expression),
        },
    };
}

pub fn parseBlockStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.OPEN_CURLY);
    var body = try std.ArrayList(*ast.Stmt).initCapacity(p.allocator, p.numTokens());

    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_CURLY) {
        const stmt = try parseStmt(p);
        const stmt_ptr = try boxStmt(p, stmt);
        try body.append(stmt_ptr);
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

    _ = try p.expect(.SEMI_COLON);

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
        av_ptr = try boxExpr(p, av);
    }

    var et_ptr: ?*ast.Type = null;
    if (explicit_type) |et| {
        et_ptr = try boxType(p, et);
    }

    return ast.Stmt{
        .var_decl = ast.VarDeclarationStmt{
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
    var function_params = std.ArrayList(*ast.Parameter).init(p.allocator);
    _ = try p.expect(.OPEN_PAREN);
    while (p.hasTokens() and p.currentTokenKind() != .CLOSE_PAREN) {
        const expected = try p.expect(.IDENTIFIER);
        const param_name = expected.value;
        _ = try p.expect(.COLON);
        const param_type = try types.parseType(p, binding.DEFAULT_BP);

        const param_ptr = try p.allocator.create(ast.Parameter);
        const param = ast.Parameter{
            .name = param_name,
            .type = try boxType(p, param_type),
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
        return_type = ast.Type{ .symbol = ast.SymbolType{
            .value = "void",
        } };
    }

    const block_stmt = try parseBlockStmt(p);
    const function_body = block_stmt.block.body;
    return FunctionInfo{
        .body = function_body,
        .parameters = function_params,
        .return_type = try boxType(p, return_type),
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
    const condition = try expr.parseExpr(p, binding.ASSIGNMENT);
    const consequent = try parseBlockStmt(p);

    var alternate: ?ast.Stmt = null;
    if (p.currentTokenKind() == .ELSE) {
        _ = p.advance();

        if (p.currentTokenKind() == .IF) {
            alternate = try parseIfStmt(p);
        } else {
            alternate = try parseBlockStmt(p);
        }
    }

    const cons_ptr = try boxStmt(p, consequent);
    var alt_ptr: ?*ast.Stmt = null;
    if (alternate) |a| {
        alt_ptr = try boxStmt(p, a);
    }
    const cond_ptr = try boxExpr(p, condition);

    return ast.Stmt{
        .if_stmt = ast.IfStmt{
            .condition = cond_ptr,
            .consequent = cons_ptr,
            .alternate = alt_ptr,
        },
    };
}

pub fn parseImportStmt(p: *parser.Parser) !ast.Stmt {
    _ = p.advance();
    var import_from: []const u8 = undefined;
    const import_type = try p.expectMany(&[_]token.TokenKind{ .IDENTIFIER, .STAR });
    const import_name = import_type.value;

    if (p.currentTokenKind() == .FROM) {
        _ = p.advance();
        import_from = (try p.expect(.STRING)).value;
    } else {
        if (std.mem.eql(u8, import_name, "*")) {
            return error.MissingWildcardFile;
        }
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
    const iterable = try expr.parseExpr(p, binding.DEFAULT_BP);
    const block_stmt = try parseBlockStmt(p);
    const body = block_stmt.block.body;

    return ast.Stmt{
        .foreach_stmt = ast.ForeachStmt{
            .value = value_name,
            .index = index,
            .iterable = try boxExpr(p, iterable),
            .body = body,
        },
    };
}

pub fn parseWhileStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.WHILE);
    const condition = try expr.parseExpr(p, binding.DEFAULT_BP);
    const block_stmt = try parseBlockStmt(p);

    return ast.Stmt{
        .while_stmt = ast.WhileStmt{
            .condition = try boxExpr(p, condition),
            .body = block_stmt.block.body,
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

pub fn parseBreakStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.BREAK);
    _ = try p.expect(.SEMI_COLON);

    return ast.Stmt{
        .break_stmt = ast.BreakStmt{},
    };
}

pub fn parseContinueStmt(p: *parser.Parser) !ast.Stmt {
    _ = try p.expect(.CONTINUE);
    _ = try p.expect(.SEMI_COLON);

    return ast.Stmt{
        .continue_stmt = ast.ContinueStmt{},
    };
}
