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

pub const ObjectExpr = struct {
    entries: std.ArrayList(*ObjectEntry),
};

pub const ObjectEntry = struct {
    key: []const u8,
    value: *Expr,
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
    object: ObjectExpr,

    pub fn toString(self: *Expr, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();
        try self.writeTo(writer);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Expr, writer: anytype) anyerror!void {
        switch (self.*) {
            .number => |n| {
                try writer.print("Number: {d}\n", .{n.value});
            },
            .string => |s| {
                try writer.print("String: \"{s}\"\n", .{s.value});
            },
            .symbol => |s| {
                try writer.print("Symbol: {s}\n", .{s.value});
            },
            .prefix => |p| {
                try writer.print("PrefixExpr: operator = {s}\n", .{try tokens.tokenKindString(p.operator.allocator, p.operator.kind)});
                try p.right.writeTo(writer);
            },
            .binary => |b| {
                try writer.print("BinaryExpr: operator = {s}\n", .{try tokens.tokenKindString(b.operator.allocator, b.operator.kind)});
                try b.left.writeTo(writer);
                try b.right.writeTo(writer);
            },
            .assignment => |a| {
                try writer.print("AssignmentExpr:\n", .{});
                try a.assignee.writeTo(writer);
                try a.assigned_value.writeTo(writer);
            },
            .member => |m| {
                try writer.print("MemberExpr: property = {s}\n", .{m.property});
                try m.member.writeTo(writer);
            },
            .computed => |c| {
                try writer.print("ComputedExpr:\n", .{});
                try c.member.writeTo(writer);
                try c.property.writeTo(writer);
            },
            .call => |c| {
                try writer.print("CallExpr:\n", .{});
                try c.method.writeTo(writer);
                for (c.arguments.items) |arg| {
                    try arg.writeTo(writer);
                }
            },
            .range_expr => |r| {
                try writer.print("RangeExpr:\n", .{});
                try r.lower.writeTo(writer);
                try r.upper.writeTo(writer);
            },
            .function_expr => |f| {
                try writer.print("FunctionExpr:\n", .{});
                try writer.print("Params:\n", .{});
                for (f.parameters.items) |param| {
                    try param.writeTo(writer);
                }
                try writer.print("Return Type:\n", .{});
                try f.return_type.writeTo(writer);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer);
                }
            },
            .array_literal => |a| {
                try writer.print("ArrayLiteral:\n", .{});
                for (a.contents.items) |item| {
                    try item.writeTo(writer);
                }
            },
            .new_expr => |n| {
                try writer.print("NewExpr:\n", .{});
                try n.instantiation.method.writeTo(writer);
                for (n.instantiation.arguments.items) |arg| {
                    try arg.writeTo(writer);
                }
            },
            .object => |obj| {
                try writer.print("ObjectExpr:\n", .{});
                for (obj.entries.items) |entry| {
                    try writer.print("  Key: {s}\n", .{entry.key});
                    try entry.value.writeTo(writer);
                }
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

pub const WhileStmt = struct {
    condition: *Expr,
    body: std.ArrayList(*Stmt),
};

pub const ClassDeclarationStmt = struct {
    name: []const u8,
    body: std.ArrayList(*Stmt),
};

pub const BreakStmt = struct {};
pub const ContinueStmt = struct {};

pub const Stmt = union(enum) {
    block: BlockStmt,
    var_decl: VarDeclarationStmt,
    expression: ExpressionStmt,
    function_decl: FunctionDeclarationStmt,
    if_stmt: IfStmt,
    import_stmt: ImportStmt,
    foreach_stmt: ForeachStmt,
    while_stmt: WhileStmt,
    class_decl: ClassDeclarationStmt,
    break_stmt: BreakStmt,
    continue_stmt: ContinueStmt,

    pub fn toString(self: *Stmt, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Stmt, writer: anytype) anyerror!void {
        switch (self.*) {
            .block => |b| {
                try writer.print("BlockStmt:\n", .{});
                for (b.body.items) |stmt| {
                    try stmt.writeTo(writer);
                }
            },
            .var_decl => |v| {
                try writer.print("VarDeclStmt: {s} (const: {})\n", .{ v.identifier, v.constant });
                if (v.explicit_type) |ty| {
                    try writer.print("Explicit Type:\n", .{});
                    try ty.writeTo(writer);
                }
                if (v.assigned_value) |val| {
                    try writer.print("Assigned Value:\n", .{});
                    try val.writeTo(writer);
                }
            },
            .expression => |e| {
                try writer.print("ExpressionStmt:\n", .{});
                try e.expression.writeTo(writer);
            },
            .function_decl => |f| {
                try writer.print("FunctionDecl: {s}\n", .{f.name});
                try writer.print("Params:\n", .{});
                for (f.parameters.items) |param| {
                    try param.writeTo(writer);
                }
                try writer.print("Return Type:\n", .{});
                try f.return_type.writeTo(writer);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer);
                }
            },
            .if_stmt => |i| {
                try writer.print("IfStmt:\n", .{});
                try writer.print("Condition:\n", .{});
                try i.condition.writeTo(writer);
                try writer.print("Consequent:\n", .{});
                try i.consequent.writeTo(writer);
                if (i.alternate) |alt| {
                    try writer.print("Alternate:\n", .{});
                    try alt.writeTo(writer);
                }
            },
            .import_stmt => |i| {
                try writer.print("ImportStmt: name = {s}, from = {s}\n", .{ i.name, i.from });
            },
            .foreach_stmt => |f| {
                try writer.print("ForeachStmt: value = {s}, index = {}\n", .{ f.value, f.index });
                try writer.print("Iterable:\n", .{});
                try f.iterable.writeTo(writer);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer);
                }
            },
            .while_stmt => |w| {
                try writer.print("While:\n", .{});
                try writer.print("Condition:\n", .{});
                try w.condition.writeTo(writer);
                try writer.print("Body:\n", .{});
                for (w.body.items) |stmt| {
                    try stmt.writeTo(writer);
                }
            },
            .class_decl => |c| {
                try writer.print("ClassDecl: {s}\n", .{c.name});
                for (c.body.items) |stmt| {
                    try stmt.writeTo(writer);
                }
            },
            .break_stmt => |_| {
                try writer.print("break\n", .{});
            },
            .continue_stmt => |_| {
                try writer.print("continue\n", .{});
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

    pub fn toString(self: *Type, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Type, writer: anytype) anyerror!void {
        switch (self.*) {
            .symbol => |s| {
                try writer.print("Type: symbol, value = {s}\n", .{s.value});
            },
            .list => |l| {
                try writer.print("Type: list of:\n", .{});
                try l.underlying.writeTo(writer);
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

        try self.writeTo(writer);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: Parameter, writer: anytype) anyerror!void {
        try writer.print("Parameter: name = {s}\n", .{self.name});
        try self.type.writeTo(writer);
    }
};
