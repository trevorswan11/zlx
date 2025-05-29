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
    left: *Expr,
    operator: tokens.Token,
    right: *Expr,
};

pub const PrefixExpr = struct {
    operator: tokens.Token,
    right: *Expr,
};

pub const AssignmentExpr = struct {
    assignee: *Expr,
    assigned_value: *Expr,
};

pub const MemberExpr = struct {
    member: *Expr,
    property: []const u8,
};

pub const CallExpr = struct {
    method: *Expr,
    arguments: std.ArrayList(*Expr),
};

pub const ComputedExpr = struct {
    member: *Expr,
    property: *Expr,
};

pub const RangeExpr = struct {
    lower: *Expr,
    upper: *Expr,
};

pub const FunctionExpr = struct {
    parameters: std.ArrayList(*Parameter),
    body: std.ArrayList(*Stmt),
    return_type: *Type,
};

pub const ArrayLiteral = struct {
    contents: std.ArrayList(*Expr),
};

pub const NewExpr = struct {
    instantiation: *CallExpr,
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

    pub fn print(self: *Expr) anyerror!void {
        const stdout = std.io.getStdOut().writer();
        switch (self.*) {
            .number => |n| try stdout.print("Number: {d}\n", .{n.value}),
            .string => |s| try stdout.print("String: \"{s}\"\n", .{s.value}),
            .symbol => |s| try stdout.print("Symbol: {s}\n", .{s.value}),
            .prefix => |p| {
                try stdout.print("PrefixExpr: operator = {s}\n", .{try tokens.tokenKindString(p.operator.allocator, p.operator.kind)});
                try p.right.print();
            },
            .binary => |b| {
                try stdout.print("BinaryExpr: operator = {s}\n", .{try tokens.tokenKindString(b.operator.allocator, b.operator.kind)});
                try b.left.print();
                try b.right.print();
            },
            .assignment => |a| {
                try stdout.print("AssignmentExpr:\n", .{});
                try a.assignee.print();
                try a.assigned_value.print();
            },
            .member => |m| {
                try stdout.print("MemberExpr: property = {s}\n", .{m.property});
                try m.member.print();
            },
            .computed => |c| {
                try stdout.print("ComputedExpr:\n", .{});
                try c.member.print();
                try c.property.print();
            },
            .call => |c| {
                try stdout.print("CallExpr:\n", .{});
                try c.method.print();
                for (c.arguments.items) |arg| {
                    try arg.print();
                }
            },
            .range_expr => |r| {
                try stdout.print("RangeExpr:\n", .{});
                try r.lower.print();
                try r.upper.print();
            },
            .function_expr => |f| {
                try stdout.print("FunctionExpr:\n", .{});
                try stdout.print("Params:\n", .{});
                for (f.parameters.items) |param| try param.print();
                try stdout.print("Return Type:\n", .{});
                try f.return_type.print();
                try stdout.print("Body:\n", .{});
                for (f.body.items) |stmt| try stmt.print();
            },
            .array_literal => |a| {
                try stdout.print("ArrayLiteral:\n", .{});
                for (a.contents.items) |item| try item.print();
            },
            .new_expr => |n| {
                try stdout.print("NewExpr:\n", .{});
                try n.instantiation.method.print();
                for (n.instantiation.arguments.items) |arg| try arg.print();
            },
        }
    }
};

// === Statements ===

pub const BlockStmt = struct {
    body: std.ArrayList(*Stmt),
};

pub const VarDeclarationStmt = struct {
    identifier: []const u8,
    constant: bool,
    assigned_value: ?*Expr,
    explicit_type: ?*Type,
};

pub const ExpressionStmt = struct {
    expression: *Expr,
};

pub const FunctionDeclarationStmt = struct {
    parameters: std.ArrayList(*Parameter),
    name: []const u8,
    body: std.ArrayList(*Stmt),
    return_type: *Type,
};

pub const IfStmt = struct {
    condition: *Expr,
    consequent: *Stmt,
    alternate: ?*Stmt,
};

pub const ImportStmt = struct {
    name: []const u8,
    from: []const u8,
};

pub const ForeachStmt = struct {
    value: []const u8,
    index: bool,
    iterable: *Expr,
    body: std.ArrayList(*Stmt),
};

pub const ClassDeclarationStmt = struct {
    name: []const u8,
    body: std.ArrayList(*Stmt),
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

    pub fn print(self: *Stmt) anyerror!void {
        const stdout = std.io.getStdOut().writer();
        switch (self.*) {
            .block => |b| {
                try stdout.print("BlockStmt:\n", .{});
                for (b.body.items) |stmt| try stmt.print();
            },
            .var_decl => |v| {
                try stdout.print("VarDeclStmt: {s} (const: {})\n", .{ v.identifier, v.constant });
                if (v.explicit_type) |ty| {
                    try stdout.print("Explicit Type:\n", .{});
                    try ty.print();
                }
                if (v.assigned_value) |val| {
                    try stdout.print("Assigned Value:\n", .{});
                    try val.print();
                }
            },
            .expression => |e| {
                try stdout.print("ExpressionStmt:\n", .{});
                try e.expression.print();
            },
            .function_decl => |f| {
                try stdout.print("FunctionDecl: {s}\n", .{f.name});
                try stdout.print("Params:\n", .{});
                for (f.parameters.items) |param| try param.print();
                try stdout.print("Return Type:\n", .{});
                try f.return_type.print();
                try stdout.print("Body:\n", .{});
                for (f.body.items) |stmt| try stmt.print();
            },
            .if_stmt => |i| {
                try stdout.print("IfStmt:\n", .{});
                try stdout.print("Condition:\n", .{});
                try i.condition.print();
                try stdout.print("Consequent:\n", .{});
                try i.consequent.print();
                if (i.alternate) |alt| {
                    try stdout.print("Alternate:\n", .{});
                    try alt.print();
                }
            },
            .import_stmt => |i| {
                try stdout.print("ImportStmt: name = {s}, from = {s}\n", .{ i.name, i.from });
            },
            .foreach_stmt => |f| {
                try stdout.print("ForeachStmt: value = {s}, index = {}\n", .{ f.value, f.index });
                try stdout.print("Iterable:\n", .{});
                try f.iterable.print();
                try stdout.print("Body:\n", .{});
                for (f.body.items) |stmt| try stmt.print();
            },
            .class_decl => |c| {
                try stdout.print("ClassDecl: {s}\n", .{c.name});
                for (c.body.items) |stmt| try stmt.print();
            },
        }
    }
};

// === Types ===

pub const SymbolType = struct {
    value: []const u8,
};

pub const ListType = struct {
    underlying: *Type,
};

pub const Type = union(enum) {
    symbol: SymbolType,
    list: ListType,

    pub fn print(self: *Type) anyerror!void {
        const stdout = std.io.getStdOut().writer();
        switch (self.*) {
            .symbol => |s| try stdout.print("Type: symbol, value = {s}\n", .{s.value}),
            .list => |l| {
                try stdout.print("Type: list of:\n", .{});
                try l.underlying.print();
            },
        }
    }
};

// === Parameter ===

pub const Parameter = struct {
    name: []const u8,
    type: *Type,

    pub fn print(self: Parameter) anyerror!void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Parameter: name = {s}\n", .{self.name});
    }
};
