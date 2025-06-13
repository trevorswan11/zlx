const std = @import("std");
const token = @import("../lexer/token.zig");

// === Shared Types ===

pub const Match = struct {
    expression: *Expr,
    cases: std.ArrayList(MatchCase),
};

pub const MatchCase = struct {
    pattern: *Expr,
    body: *Stmt,
};

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
    operator: token.Token,
    right: *Expr,
};

pub const PrefixExpr = struct {
    operator: token.Token,
    right: *Expr,
};

pub const PostfixExpr = struct {
    operator: token.Token,
    left: *Expr,
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

pub const ObjectExpr = struct {
    entries: std.ArrayList(*ObjectEntry),
};

pub const ObjectEntry = struct {
    key: []const u8,
    value: *Expr,
};

pub const CompoundAssignmentExpr = struct {
    assignee: *Expr,
    operator: token.Token,
    value: *Expr,
};

pub const Expr = union(enum) {
    number: NumberExpr,
    string: StringExpr,
    boolean: bool,
    symbol: SymbolExpr,
    binary: BinaryExpr,
    prefix: PrefixExpr,
    postfix: PostfixExpr,
    assignment: AssignmentExpr,
    member: MemberExpr,
    call: CallExpr,
    computed: ComputedExpr,
    range_expr: RangeExpr,
    function_expr: FunctionExpr,
    array_literal: ArrayLiteral,
    new_expr: NewExpr,
    object: ObjectExpr,
    match_expr: Match,
    compound_assignment: CompoundAssignmentExpr,
    nil: void,

    pub fn toString(self: *Expr, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();
        try self.writeTo(writer, 0);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Expr, writer: anytype, indent_level: usize) anyerror!void {
        switch (self.*) {
            .number => |n| {
                try indent(writer, indent_level);
                try writer.print("Number: {d}\n", .{n.value});
            },
            .string => |s| {
                try indent(writer, indent_level);
                try writer.print("String: \"{s}\"\n", .{s.value});
            },
            .boolean => |b| {
                try indent(writer, indent_level);
                try writer.print("Boolean: {}\n", .{b});
            },
            .symbol => |s| {
                try indent(writer, indent_level);
                try writer.print("Symbol: {s}\n", .{s.value});
            },
            .prefix => |p| {
                try indent(writer, indent_level);
                try writer.print("PrefixExpr: operator = {s}\n", .{
                    try token.tokenKindString(p.operator.allocator, p.operator.kind),
                });
                try p.right.writeTo(writer, indent_level + 1);
            },
            .postfix => |p| {
                try indent(writer, indent_level);
                try writer.print("PostfixExpr: operator = {s}\n", .{
                    try token.tokenKindString(p.operator.allocator, p.operator.kind),
                });
                try p.left.writeTo(writer, indent_level + 1);
            },
            .binary => |b| {
                try indent(writer, indent_level);
                try writer.print("BinaryExpr: operator = {s}\n", .{
                    try token.tokenKindString(b.operator.allocator, b.operator.kind),
                });
                try b.left.writeTo(writer, indent_level + 1);
                try b.right.writeTo(writer, indent_level + 1);
            },
            .assignment => |a| {
                try indent(writer, indent_level);
                try writer.print("AssignmentExpr:\n", .{});
                try a.assignee.writeTo(writer, indent_level + 1);
                try a.assigned_value.writeTo(writer, indent_level + 1);
            },
            .member => |m| {
                try indent(writer, indent_level);
                try writer.print("MemberExpr: property = {s}\n", .{m.property});
                try m.member.writeTo(writer, indent_level + 1);
            },
            .computed => |c| {
                try indent(writer, indent_level);
                try writer.print("ComputedExpr:\n", .{});
                try c.member.writeTo(writer, indent_level + 1);
                try c.property.writeTo(writer, indent_level + 1);
            },
            .call => |c| {
                try indent(writer, indent_level);
                try writer.print("CallExpr:\n", .{});
                try c.method.writeTo(writer, indent_level + 1);
                for (c.arguments.items) |arg| {
                    try arg.writeTo(writer, indent_level + 1);
                }
            },
            .range_expr => |r| {
                try indent(writer, indent_level);
                try writer.print("RangeExpr:\n", .{});
                try r.lower.writeTo(writer, indent_level + 1);
                try r.upper.writeTo(writer, indent_level + 1);
            },
            .function_expr => |f| {
                try indent(writer, indent_level);
                try writer.print("FunctionExpr:\n", .{});
                try indent(writer, indent_level + 1);
                try writer.print("Params:\n", .{});
                for (f.parameters.items) |param| {
                    try param.writeTo(writer, indent_level + 2);
                }
                try indent(writer, indent_level + 1);
                try writer.print("Return Type:\n", .{});
                try f.return_type.writeTo(writer, indent_level + 2);
                try indent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .array_literal => |a| {
                try indent(writer, indent_level);
                try writer.print("ArrayLiteral:\n", .{});
                for (a.contents.items) |item| {
                    try item.writeTo(writer, indent_level + 1);
                }
            },
            .new_expr => |n| {
                try indent(writer, indent_level);
                try writer.print("NewExpr:\n", .{});
                try n.instantiation.method.writeTo(writer, indent_level + 1);
                for (n.instantiation.arguments.items) |arg| {
                    try arg.writeTo(writer, indent_level + 1);
                }
            },
            .object => |obj| {
                try indent(writer, indent_level);
                try writer.print("ObjectExpr:\n", .{});
                for (obj.entries.items) |entry| {
                    try indent(writer, indent_level + 1);
                    try writer.print("Key: {s}\n", .{entry.key});
                    try entry.value.writeTo(writer, indent_level + 2);
                }
            },
            .match_expr => |m| {
                try indent(writer, indent_level);
                try writer.print("MatchStmt:\n", .{});
                try indent(writer, indent_level + 1);
                try writer.print("Expression:\n", .{});
                try m.expression.writeTo(writer, indent_level + 2);

                try indent(writer, indent_level + 1);
                try writer.print("Case(s):\n", .{});
                for (m.cases.items) |stmt| {
                    try indent(writer, indent_level + 2);
                    try writer.print("Pattern:\n", .{});
                    try stmt.pattern.writeTo(writer, indent_level + 3);

                    try indent(writer, indent_level + 2);
                    try writer.print("Body:\n", .{});
                    try stmt.body.writeTo(writer, indent_level + 3);
                }
            },
            .compound_assignment => |c| {
                try indent(writer, indent_level);
                try writer.print("Compound Assignment:\n", .{});
                try indent(writer, indent_level + 1);
                try c.assignee.writeTo(writer, indent_level + 2);
                try indent(writer, indent_level + 1);
                try writer.print("Operator: {s}\n", .{@tagName(c.operator.kind)});
                try indent(writer, indent_level + 1);
                try c.value.writeTo(writer, indent_level + 2);
            },
            .nil => {
                try indent(writer, indent_level);
                try writer.print("nil\n", .{});
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
    index_name: ?[]const u8,
    iterable: *Expr,
    body: std.ArrayList(*Stmt),
};

pub const WhileStmt = struct {
    condition: *Expr,
    body: std.ArrayList(*Stmt),
};

pub const StructDeclarationStmt = struct {
    name: []const u8,
    body: std.ArrayList(*Stmt),
};

pub const BreakStmt = struct {};
pub const ContinueStmt = struct {};

pub const ReturnStmt = struct {
    value: ?*Expr,
};

pub const Stmt = union(enum) {
    block: BlockStmt,
    var_decl: VarDeclarationStmt,
    expression: ExpressionStmt,
    function_decl: FunctionDeclarationStmt,
    if_stmt: IfStmt,
    import_stmt: ImportStmt,
    foreach_stmt: ForeachStmt,
    while_stmt: WhileStmt,
    struct_decl: StructDeclarationStmt,
    break_stmt: BreakStmt,
    continue_stmt: ContinueStmt,
    return_stmt: ReturnStmt,
    match_stmt: Match,

    pub fn toString(self: *Stmt, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer, 0);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Stmt, writer: anytype, indent_level: usize) anyerror!void {
        switch (self.*) {
            .block => |b| {
                try indent(writer, indent_level);
                try writer.print("BlockStmt:\n", .{});
                for (b.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 1);
                }
            },
            .var_decl => |v| {
                try indent(writer, indent_level);
                try writer.print("VarDeclStmt: {s} (const: {})\n", .{ v.identifier, v.constant });
                if (v.explicit_type) |ty| {
                    try indent(writer, indent_level + 1);
                    try writer.print("Explicit Type:\n", .{});
                    try ty.writeTo(writer, indent_level + 2);
                }
                if (v.assigned_value) |val| {
                    try indent(writer, indent_level + 1);
                    try writer.print("Assigned Value:\n", .{});
                    try val.writeTo(writer, indent_level + 2);
                }
            },
            .expression => |e| {
                try indent(writer, indent_level);
                try writer.print("ExpressionStmt:\n", .{});
                try e.expression.writeTo(writer, indent_level + 1);
            },
            .function_decl => |f| {
                try indent(writer, indent_level);
                try writer.print("FunctionDecl: {s}\n", .{f.name});
                try indent(writer, indent_level + 1);
                try writer.print("Params:\n", .{});
                for (f.parameters.items) |param| {
                    try param.writeTo(writer, indent_level + 2);
                }
                try indent(writer, indent_level + 1);
                try writer.print("Return Type:\n", .{});
                try f.return_type.writeTo(writer, indent_level + 2);
                try indent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .if_stmt => |i| {
                try indent(writer, indent_level);
                try writer.print("IfStmt:\n", .{});
                try indent(writer, indent_level + 1);
                try writer.print("Condition:\n", .{});
                try i.condition.writeTo(writer, indent_level + 2);
                try indent(writer, indent_level + 1);
                try writer.print("Consequent:\n", .{});
                try i.consequent.writeTo(writer, indent_level + 2);
                if (i.alternate) |alt| {
                    try indent(writer, indent_level + 1);
                    try writer.print("Alternate:\n", .{});
                    try alt.writeTo(writer, indent_level + 2);
                }
            },
            .import_stmt => |i| {
                try indent(writer, indent_level);
                try writer.print("ImportStmt: name = {s}, from = {s}\n", .{ i.name, i.from });
            },
            .foreach_stmt => |f| {
                try indent(writer, indent_level);
                try writer.print("ForeachStmt: value = {s}, index = {}\n", .{ f.value, f.index });
                try indent(writer, indent_level + 1);
                try writer.print("Iterable:\n", .{});
                try f.iterable.writeTo(writer, indent_level + 2);
                try indent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .while_stmt => |w| {
                try indent(writer, indent_level);
                try writer.print("WhileStmt:\n", .{});
                try indent(writer, indent_level + 1);
                try writer.print("Condition:\n", .{});
                try w.condition.writeTo(writer, indent_level + 2);
                try indent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (w.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .struct_decl => |c| {
                try indent(writer, indent_level);
                try writer.print("ClassDecl: {s}\n", .{c.name});
                for (c.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 1);
                }
            },
            .break_stmt => |_| {
                try indent(writer, indent_level);
                try writer.print("break\n", .{});
            },
            .continue_stmt => |_| {
                try indent(writer, indent_level);
                try writer.print("continue\n", .{});
            },
            .return_stmt => |r| {
                try indent(writer, indent_level);
                try writer.print("ReturnStmt:\n", .{});
                if (r.value) |v| {
                    try v.writeTo(writer, indent_level + 1);
                } else {
                    try indent(writer, indent_level + 1);
                    try writer.print("void\n", .{});
                }
            },
            .match_stmt => |m| {
                try indent(writer, indent_level);
                try writer.print("MatchStmt:\n", .{});
                try indent(writer, indent_level + 1);
                try writer.print("Expression:\n", .{});
                try m.expression.writeTo(writer, indent_level + 2);

                try indent(writer, indent_level + 1);
                try writer.print("Case(s):\n", .{});
                for (m.cases.items) |stmt| {
                    try indent(writer, indent_level + 2);
                    try writer.print("Pattern:\n", .{});
                    try stmt.pattern.writeTo(writer, indent_level + 3);

                    try indent(writer, indent_level + 2);
                    try writer.print("Body:\n", .{});
                    try stmt.body.writeTo(writer, indent_level + 3);
                }
            },
        }
    }
};

// === Types ===

pub const SymbolType = struct {
    value_type: []const u8,
};

pub const ListType = struct {
    underlying: *Type,
};

pub const Type = union(enum) {
    symbol: SymbolType,
    list: ListType,

    pub fn toString(self: *Type, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer, 0);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Type, writer: anytype, indent_level: usize) anyerror!void {
        switch (self.*) {
            .symbol => |s| {
                try indent(writer, indent_level);
                try writer.print("Type: symbol, value type = \"{s}\"\n", .{s.value_type});
            },
            .list => |l| {
                try indent(writer, indent_level);
                try writer.print("Type: list of:\n", .{});
                try l.underlying.writeTo(writer, indent_level + 1);
            },
        }
    }
};

// === Parameter ===

pub const Parameter = struct {
    name: []const u8,
    type: *Type,

    pub fn toString(self: Parameter, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer, 0);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: Parameter, writer: anytype, indent_level: usize) anyerror!void {
        try indent(writer, indent_level);
        try writer.print("Parameter: name = {s}\n", .{self.name});
        try self.type.writeTo(writer, indent_level + 1);
    }
};

fn indent(writer: anytype, level: usize) !void {
    for (0..level) |_| {
        try writer.writeAll("  ");
    }
}

// === Memory Safety ===
const Parser = @import("parser.zig").Parser;

pub fn boxExpr(p: *Parser, e: Expr) !*Expr {
    const ptr = try p.allocator.create(Expr);
    ptr.* = e;
    return ptr;
}

pub fn boxStmt(p: *Parser, stmt: Stmt) !*Stmt {
    const ptr = try p.allocator.create(Stmt);
    ptr.* = stmt;
    return ptr;
}

pub fn boxType(p: *Parser, e: Type) !*Type {
    const ptr = try p.allocator.create(Type);
    ptr.* = e;
    return ptr;
}
