const std = @import("std");

const ast = @import("ast.zig");
const tokens = @import("../lexer/token.zig");

pub const BlockStmt = struct {
    body: std.ArrayList(ast.Stmt),
    allocator: std.mem.Allocator,

    pub fn stmt(self: BlockStmt) void {
        _ = self;
    }
};

pub const ExpressionStmt = struct {
    expression: ast.Expr,

    pub fn stmt(self: ExpressionStmt) void {
        _ = self;
    }
};