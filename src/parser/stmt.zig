const std = @import("std");

const parser = @import("parser.zig");
const token = @import("../lexer/token.zig");
const ast = @import("../ast/ast.zig");
const stmts = @import("../ast/statements.zig");

pub fn parseStmt(p: *parser.Parser) ast.Stmt {
    _ = p;
    std.debug.print("Not implemented!\n", .{});
}