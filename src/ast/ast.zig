const std = @import("std");
const tokens = @import("../lexer/token.zig");

// === Expressions ===

pub const NumberExpr = struct {
    value: f64,
};

pub const StringExpr = struct {
    value: []const u8,
};

pub const SymbolExpr = struct {
    value: []const u8,
};

pub const BinaryExpr = struct {
    left: Expr,
    operator: tokens.Token,
    right: Expr,
};

pub const PrefixExpr = struct {
    operator: tokens.Token,
    right: Expr,
};

pub const AssignmentExpr = struct {
    assignee: Expr,
    assigned_value: Expr,
};

pub const MemberExpr = struct {
    member: Expr,
    property: []const u8,
};

pub const CallExpr = struct {
    method: Expr,
    arguments: std.ArrayList(Expr),
};

pub const ComputedExpr = struct {
    member: Expr,
    property: Expr,
};

pub const RangeExpr = struct {
    lower: Expr,
    upper: Expr,
};

pub const FunctionExpr = struct {
    parameters: std.ArrayList(Parameter),
    body: std.ArrayList(Stmt),
    return_type: Type,
};

pub const ArrayLiteral = struct {
    contents: std.ArrayList(Expr),
};

pub const NewExpr = struct {
    instantiation: CallExpr,
};

pub const Expr = union(enum) {
    number: NumberExpr,
    string: StringExpr,
    symbol: SymbolExpr,
    binary: BinaryExpr,
    prefix: PrefixExpr,
    assignment: AssignmentExpr,
    member: MemberExpr,
    call: CallExpr,
    computed: ComputedExpr,
    range_expr: RangeExpr,
    function_expr: FunctionExpr,
    array_literal: ArrayLiteral,
    new_expr: NewExpr,

    pub fn print(self: Expr) void {
        switch (self) {
            .number => |n| std.debug.print("Number: {d}\n", .{n.value}),
            .symbol => |s| std.debug.print("Symbol: {s}\n", .{s.value}),
            else => std.debug.print("Expr variant: {s}\n", .{@tagName(self)}),
        }
    }
};

// === Statements ===

pub const BlockStmt = struct {
    body: std.ArrayList(Stmt),
};

pub const VarDeclarationStmt = struct {
    identifier: []const u8,
    constant: bool,
    assigned_value: Expr,
    explicit_type: Type,
};

pub const ExpressionStmt = struct {
    expression: Expr,
};

pub const FunctionDeclarationStmt = struct {
    parameters: std.ArrayList(Parameter),
    name: []const u8,
    body: std.ArrayList(Stmt),
    return_type: Type,
};

pub const IfStmt = struct {
    condition: Expr,
    consequent: Stmt,
    alternate: ?Stmt,
};

pub const ImportStmt = struct {
    name: []const u8,
    from: []const u8,
};

pub const ForeachStmt = struct {
    value: []const u8,
    index: bool,
    iterable: Expr,
    body: std.ArrayList(Stmt),
};

pub const ClassDeclarationStmt = struct {
    name: []const u8,
    body: std.ArrayList(Stmt),
};

pub const Stmt = union(enum) {
    block: BlockStmt,
    var_decl: VarDeclarationStmt,
    expression: ExpressionStmt,
    function_decl: FunctionDeclarationStmt,
    if_stmt: IfStmt,
    import_stmt: ImportStmt,
    foreach_stmt: ForeachStmt,
    class_decl: ClassDeclarationStmt,

    pub fn print(self: Stmt) void {
        std.debug.print("Stmt: {s}\n", .{@tagName(self)});
    }
};

// === Types ===

pub const SymbolType = struct {
    value: []const u8,
};

pub const ListType = struct {
    underlying: Type,
};

pub const Type = union(enum) {
    symbol: SymbolType,
    list: ListType,

    pub fn print(self: Type) void {
        switch (self) {
            .symbol => |s| std.debug.print("Type: symbol({s})\n", .{s.value}),
            .list => |_| std.debug.print("Type: list\n", .{}),
        }
    }
};

// === Parameter ===

pub fn Parameter(comptime T: type) type {
    return struct {
        name: []const u8,
        param_type: Type(T),
    };
}
