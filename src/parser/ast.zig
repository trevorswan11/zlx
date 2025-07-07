const std = @import("std");

const token = @import("../lexer/token.zig");
const driver = @import("../utils/driver.zig");

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
                try stdoutIndent(writer, indent_level);
                try writer.print("Number: {d}\n", .{n.value});
            },
            .string => |s| {
                try stdoutIndent(writer, indent_level);
                try writer.print("String: \"{s}\"\n", .{s.value});
            },
            .boolean => |b| {
                try stdoutIndent(writer, indent_level);
                try writer.print("Boolean: {}\n", .{b});
            },
            .symbol => |s| {
                try stdoutIndent(writer, indent_level);
                try writer.print("Symbol: {s}\n", .{s.value});
            },
            .prefix => |p| {
                try stdoutIndent(writer, indent_level);
                try writer.print("PrefixExpr: operator = {s}\n", .{
                    try token.tokenKindString(p.operator.allocator, p.operator.kind),
                });
                try p.right.writeTo(writer, indent_level + 1);
            },
            .postfix => |p| {
                try stdoutIndent(writer, indent_level);
                try writer.print("PostfixExpr: operator = {s}\n", .{
                    try token.tokenKindString(p.operator.allocator, p.operator.kind),
                });
                try p.left.writeTo(writer, indent_level + 1);
            },
            .binary => |b| {
                try stdoutIndent(writer, indent_level);
                try writer.print("BinaryExpr: operator = {s}\n", .{
                    try token.tokenKindString(b.operator.allocator, b.operator.kind),
                });
                try b.left.writeTo(writer, indent_level + 1);
                try b.right.writeTo(writer, indent_level + 1);
            },
            .assignment => |a| {
                try stdoutIndent(writer, indent_level);
                try writer.print("AssignmentExpr:\n", .{});
                try a.assignee.writeTo(writer, indent_level + 1);
                try a.assigned_value.writeTo(writer, indent_level + 1);
            },
            .member => |m| {
                try stdoutIndent(writer, indent_level);
                try writer.print("MemberExpr: property = {s}\n", .{m.property});
                try m.member.writeTo(writer, indent_level + 1);
            },
            .computed => |c| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ComputedExpr:\n", .{});
                try c.member.writeTo(writer, indent_level + 1);
                try c.property.writeTo(writer, indent_level + 1);
            },
            .call => |c| {
                try stdoutIndent(writer, indent_level);
                try writer.print("CallExpr:\n", .{});
                try c.method.writeTo(writer, indent_level + 1);
                for (c.arguments.items) |arg| {
                    try arg.writeTo(writer, indent_level + 1);
                }
            },
            .range_expr => |r| {
                try stdoutIndent(writer, indent_level);
                try writer.print("RangeExpr:\n", .{});
                try r.lower.writeTo(writer, indent_level + 1);
                try r.upper.writeTo(writer, indent_level + 1);
            },
            .function_expr => |f| {
                try stdoutIndent(writer, indent_level);
                try writer.print("FunctionExpr:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Params:\n", .{});
                for (f.parameters.items) |param| {
                    try param.writeTo(writer, indent_level + 2);
                }
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Return Type:\n", .{});
                try f.return_type.writeTo(writer, indent_level + 2);
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .array_literal => |a| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ArrayLiteral:\n", .{});
                for (a.contents.items) |item| {
                    try item.writeTo(writer, indent_level + 1);
                }
            },
            .new_expr => |n| {
                try stdoutIndent(writer, indent_level);
                try writer.print("NewExpr:\n", .{});
                try n.instantiation.method.writeTo(writer, indent_level + 1);
                for (n.instantiation.arguments.items) |arg| {
                    try arg.writeTo(writer, indent_level + 1);
                }
            },
            .object => |obj| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ObjectExpr:\n", .{});
                for (obj.entries.items) |entry| {
                    try stdoutIndent(writer, indent_level + 1);
                    try writer.print("Key: {s}\n", .{entry.key});
                    try entry.value.writeTo(writer, indent_level + 2);
                }
            },
            .match_expr => |m| {
                try stdoutIndent(writer, indent_level);
                try writer.print("MatchStmt:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Expression:\n", .{});
                try m.expression.writeTo(writer, indent_level + 2);

                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Case(s):\n", .{});
                for (m.cases.items) |stmt| {
                    try stdoutIndent(writer, indent_level + 2);
                    try writer.print("Pattern:\n", .{});
                    try stmt.pattern.writeTo(writer, indent_level + 3);

                    try stdoutIndent(writer, indent_level + 2);
                    try writer.print("Body:\n", .{});
                    try stmt.body.writeTo(writer, indent_level + 3);
                }
            },
            .compound_assignment => |c| {
                try stdoutIndent(writer, indent_level);
                try writer.print("Compound Assignment:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try c.assignee.writeTo(writer, indent_level + 2);
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Operator: {s}\n", .{@tagName(c.operator.kind)});
                try stdoutIndent(writer, indent_level + 1);
                try c.value.writeTo(writer, indent_level + 2);
            },
            .nil => {
                try stdoutIndent(writer, indent_level);
                try writer.print("nil\n", .{});
            },
        }
    }

    pub fn fmtTo(self: *Expr, writer: anytype, indent_level: usize) anyerror!void {
        switch (self.*) {
            .number => |n| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{d}", .{n.value});
            },
            .string => |s| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{s}", .{s.value});
            },
            .boolean => |b| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{s}", .{if (b) "true" else "false"});
            },
            .symbol => |s| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{s}", .{s.value});
            },
            .prefix => |p| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{s}", .{p.operator.value});
                try p.right.fmtTo(writer, 0);
            },
            .postfix => |p| {
                try canonicalIndent(writer, indent_level);
                try p.left.fmtTo(writer, 0);
                try writer.print("{s}", .{p.operator.value});
            },
            .binary => |b| {
                try canonicalIndent(writer, indent_level);
                try b.left.fmtTo(writer, 0);
                try writer.print(" {s} ", .{b.operator.value});
                try b.right.fmtTo(writer, 0);
            },
            .assignment => |a| {
                try canonicalIndent(writer, indent_level);
                try a.assignee.fmtTo(writer, 0);
                try writer.print(" = ", .{});
                try a.assigned_value.fmtTo(writer, 0);
            },
            .member => |m| {
                try canonicalIndent(writer, indent_level);
                try m.member.fmtTo(writer, 0);
                try writer.print(".{s}", .{m.property});
            },
            .computed => |c| {
                try canonicalIndent(writer, indent_level);
                try c.member.fmtTo(writer, 0);
                try writer.print("[", .{});
                try c.property.fmtTo(writer, 0);
                try writer.print("]", .{});
            },
            .call => |c| {
                try canonicalIndent(writer, indent_level);
                try c.method.fmtTo(writer, 0);
                try writer.print("(", .{});
                for (c.arguments.items, 0..) |arg, i| {
                    try arg.fmtTo(writer, 0);
                    if (i != c.arguments.items.len) {
                        try writer.print(", ", .{});
                    }
                }
                try writer.print(")", .{});
            },
            .range_expr => |r| {
                try canonicalIndent(writer, indent_level);
                try r.lower.fmtTo(writer, 0);
                try writer.print("..", .{});
                try r.upper.fmtTo(writer, 0);
            },
            .function_expr => |f| {
                try canonicalIndent(writer, indent_level);
                try writer.print("fn(", .{});
                for (f.parameters.items, 0..) |param, i| {
                    try param.fmtTo(writer, 0);
                    if (i != f.parameters.items.len) {
                        try writer.print(", ", .{});
                    }
                }
                try writer.print(")", .{});
                try f.return_type.fmtTo(writer, 0);
                try writer.print("{{\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.fmtTo(writer, indent_level + 1);
                }
                try writer.print("\n}}", .{});
            },
            .array_literal => |a| {
                try canonicalIndent(writer, indent_level);
                try writer.print("[", .{});
                for (a.contents.items, 0..) |val, i| {
                    try val.fmtTo(writer, 0);
                    if (i != a.contents.items.len) {
                        try writer.print(", ", .{});
                    }
                }
                try writer.print("]", .{});
            },
            .new_expr => |n| {
                try canonicalIndent(writer, indent_level);
                try writer.print("new ", .{});
                try n.instantiation.method.fmtTo(writer, 0);
                try writer.print("(", .{});
                for (n.instantiation.arguments.items, 0..) |arg, i| {
                    try arg.fmtTo(writer, 0);
                    if (i != n.instantiation.arguments.items.len) {
                        try writer.print(", ", .{});
                    }
                }
                try writer.print(")", .{});
            },
            .object => |obj| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{{\n", .{});
                for (obj.entries.items) |entry| {
                    try canonicalIndent(writer, indent_level + 1);
                    try writer.print("{s}: ", .{entry.key});
                    try entry.value.fmtTo(writer, 0);
                    try writer.print(",\n", .{});
                }
                try writer.print("}}", .{});
            },
            .match_expr => |m| {
                try canonicalIndent(writer, indent_level);
                try writer.print("match ", .{});
                try writer.print("{{\n", .{});
                try m.expression.fmtTo(writer, 0);
                for (m.cases.items) |case| {
                    try case.pattern.fmtTo(writer, indent_level + 1);
                    try writer.print(" => ", .{});
                    try writer.print("{{\n", .{});
                    try case.body.fmtTo(writer, indent_level + 2);
                    try writer.print("}},\n", .{});
                }
                try writer.print("}}", .{});
            },
            .compound_assignment => |c| {
                try canonicalIndent(writer, indent_level);
                try c.assignee.fmtTo(writer, 0);
                try writer.print(" {s} ", .{c.operator.value});
                try c.value.fmtTo(writer, 0);
            },
            .nil => {
                try canonicalIndent(writer, indent_level);
                try writer.print("nil", .{});
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

pub const EnumDeclarationStmt = struct {
    name: []const u8,
    variants: []const []const u8,
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
    enum_decl: EnumDeclarationStmt,

    pub fn toString(self: *Stmt, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer, 0);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Stmt, writer: anytype, indent_level: usize) anyerror!void {
        switch (self.*) {
            .block => |b| {
                try stdoutIndent(writer, indent_level);
                try writer.print("BlockStmt:\n", .{});
                for (b.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 1);
                }
            },
            .var_decl => |v| {
                try stdoutIndent(writer, indent_level);
                try writer.print("VarDeclStmt: {s} (const: {})\n", .{ v.identifier, v.constant });
                if (v.explicit_type) |ty| {
                    try stdoutIndent(writer, indent_level + 1);
                    try writer.print("Explicit Type:\n", .{});
                    try ty.writeTo(writer, indent_level + 2);
                }
                if (v.assigned_value) |val| {
                    try stdoutIndent(writer, indent_level + 1);
                    try writer.print("Assigned Value:\n", .{});
                    try val.writeTo(writer, indent_level + 2);
                }
            },
            .expression => |e| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ExpressionStmt:\n", .{});
                try e.expression.writeTo(writer, indent_level + 1);
            },
            .function_decl => |f| {
                try stdoutIndent(writer, indent_level);
                try writer.print("FunctionDecl: {s}\n", .{f.name});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Params:\n", .{});
                for (f.parameters.items) |param| {
                    try param.writeTo(writer, indent_level + 2);
                }
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Return Type:\n", .{});
                try f.return_type.writeTo(writer, indent_level + 2);
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .if_stmt => |i| {
                try stdoutIndent(writer, indent_level);
                try writer.print("IfStmt:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Condition:\n", .{});
                try i.condition.writeTo(writer, indent_level + 2);
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Consequent:\n", .{});
                try i.consequent.writeTo(writer, indent_level + 2);
                if (i.alternate) |alt| {
                    try stdoutIndent(writer, indent_level + 1);
                    try writer.print("Alternate:\n", .{});
                    try alt.writeTo(writer, indent_level + 2);
                }
            },
            .import_stmt => |i| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ImportStmt: name = {s}, from = {s}\n", .{ i.name, i.from });
            },
            .foreach_stmt => |f| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ForeachStmt: value = {s}, index = {}\n", .{ f.value, f.index });
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Iterable:\n", .{});
                try f.iterable.writeTo(writer, indent_level + 2);
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .while_stmt => |w| {
                try stdoutIndent(writer, indent_level);
                try writer.print("WhileStmt:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Condition:\n", .{});
                try w.condition.writeTo(writer, indent_level + 2);
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Body:\n", .{});
                for (w.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 2);
                }
            },
            .struct_decl => |c| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ClassDecl: {s}\n", .{c.name});
                for (c.body.items) |stmt| {
                    try stmt.writeTo(writer, indent_level + 1);
                }
            },
            .break_stmt => |_| {
                try stdoutIndent(writer, indent_level);
                try writer.print("break\n", .{});
            },
            .continue_stmt => |_| {
                try stdoutIndent(writer, indent_level);
                try writer.print("continue\n", .{});
            },
            .return_stmt => |r| {
                try stdoutIndent(writer, indent_level);
                try writer.print("ReturnStmt:\n", .{});
                if (r.value) |v| {
                    try v.writeTo(writer, indent_level + 1);
                } else {
                    try stdoutIndent(writer, indent_level + 1);
                    try writer.print("void\n", .{});
                }
            },
            .match_stmt => |m| {
                try stdoutIndent(writer, indent_level);
                try writer.print("MatchStmt:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Expression:\n", .{});
                try m.expression.writeTo(writer, indent_level + 2);

                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Case(s):\n", .{});
                for (m.cases.items) |stmt| {
                    try stdoutIndent(writer, indent_level + 2);
                    try writer.print("Pattern:\n", .{});
                    try stmt.pattern.writeTo(writer, indent_level + 3);

                    try stdoutIndent(writer, indent_level + 2);
                    try writer.print("Body:\n", .{});
                    try stmt.body.writeTo(writer, indent_level + 3);
                }
            },
            .enum_decl => |e| {
                try stdoutIndent(writer, indent_level);
                try writer.print("EnumDecl:\n", .{});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Name: {s}\n", .{e.name});
                try stdoutIndent(writer, indent_level + 1);
                try writer.print("Variants:\n", .{});
                for (e.variants) |variant| {
                    try stdoutIndent(writer, indent_level + 2);
                    try writer.print("{s}\n", .{variant});
                }
            },
        }
    }

    pub fn fmtTo(self: *Stmt, writer: anytype, indent_level: usize) anyerror!void {
        switch (self.*) {
            .block => |b| {
                try canonicalIndent(writer, indent_level);
                for (b.body.items) |stmt| {
                    try stmt.fmtTo(writer, 0);
                    try writer.print("\n", .{});
                }
            },
            .var_decl => |v| {
                try canonicalIndent(writer, indent_level);
                try writer.print("{s} {s}", .{ if (v.constant) "const" else "let", v.identifier });
                if (v.explicit_type) |et| {
                    try et.fmtTo(writer, 0);
                }

                if (v.assigned_value) |av| {
                    try writer.print(" = ", .{});
                    try av.fmtTo(writer, 0);
                }
                try writer.print(";", .{});
            },
            .expression => |e| {
                try canonicalIndent(writer, indent_level);
                try e.expression.fmtTo(writer, 0);
            },
            .function_decl => |f| {
                try canonicalIndent(writer, indent_level);
                try writer.print("fn {s}(", .{f.name});
                for (f.parameters.items, 0..) |param, i| {
                    try param.fmtTo(writer, 0);
                    if (i != f.parameters.items.len) {
                        try writer.print(", ", .{});
                    }
                }
                try writer.print(")", .{});
                try f.return_type.fmtTo(writer, 0);
                try writer.print("{{\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.fmtTo(writer, indent_level + 1);
                }
                try writer.print("\n}}", .{});
            },
            .if_stmt => |i| {
                try canonicalIndent(writer, indent_level);
                try writer.print("if ", .{});
                try i.condition.fmtTo(writer, 0);
                try writer.print("{{\n", .{});
                try i.consequent.fmtTo(writer, indent_level + 1);
                try writer.print("\n}}", .{});
                if (i.alternate) |alt| {
                    try writer.print("else ", .{});
                    try alt.fmtTo(writer, 0);
                }
            },
            .import_stmt => |i| {
                try canonicalIndent(writer, indent_level);
                const reserved_map = token.reserved_identifiers;
                var r: *std.StringHashMap(token.TokenKind) = undefined;
                if (reserved_map) |res| {
                    r = res;
                } else {
                    try driver.getWriterErr().print("Reserved identifier map uninitialized\n", .{});
                    return error.MissingReservedMap;
                }

                if (r.contains(i.from)) {
                    try writer.print("import {s};", .{i.name});
                } else {
                    try writer.print("import {s} from {s};", .{ i.name, i.from });
                }
            },
            .foreach_stmt => |f| {
                try canonicalIndent(writer, indent_level);
                try writer.print("for {s}", .{f.value});
                if (f.index_name) |idx| {
                    if (f.index) {
                        try writer.print(", {s}", .{idx});
                    }
                }
                try writer.print(" in ", .{});
                try f.iterable.fmtTo(writer, 0);
                try writer.print("{{\n", .{});
                for (f.body.items) |stmt| {
                    try stmt.fmtTo(writer, indent_level + 1);
                }
                try writer.print("\n}}", .{});
            },
            .while_stmt => |w| {
                try canonicalIndent(writer, indent_level);
                try writer.print("while ", .{});
                try writer.print("{{\n", .{});
                for (w.body.items) |stmt| {
                    try stmt.fmtTo(writer, indent_level + 1);
                }
                try writer.print("\n}}", .{});
            },
            .struct_decl => |c| {
                try canonicalIndent(writer, indent_level);

                try writer.print("struct {s} {{\n", .{c.name});
                for (c.body.items) |stmt| {
                    try stmt.fmtTo(writer, indent_level + 1);
                }
                try writer.print("\n}}", .{});
            },
            .break_stmt => {
                try canonicalIndent(writer, indent_level);
                try writer.print("break;", .{});
            },
            .continue_stmt => {
                try canonicalIndent(writer, indent_level);
                try writer.print("continue;", .{});
            },
            .return_stmt => |r| {
                try canonicalIndent(writer, indent_level);
                if (r.value) |expr| {
                    try writer.print("return ", .{});
                    try expr.fmtTo(writer, 0);
                    try writer.print(";", .{});
                }
                try writer.print("return;", .{});
            },
            .match_stmt => |m| {
                try canonicalIndent(writer, indent_level);
                try writer.print("match ", .{});
                try writer.print("{{\n", .{});
                try m.expression.fmtTo(writer, 0);
                for (m.cases.items) |case| {
                    try case.pattern.fmtTo(writer, indent_level + 1);
                    try writer.print(" => ", .{});
                    try writer.print("{{\n", .{});
                    try case.body.fmtTo(writer, indent_level + 2);
                    try writer.print("}},\n", .{});
                }
                try writer.print("}}", .{});
            },
            .enum_decl => |e| {
                try canonicalIndent(writer, indent_level);
                try writer.print("enum {s} {{\n", .{e.name});
                for (e.variants) |variant| {
                    try writer.print("{s},\n", .{variant});
                }
                try writer.print("}}", .{});
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
                try stdoutIndent(writer, indent_level);
                try writer.print("Type: symbol, value type = \"{s}\"\n", .{s.value_type});
            },
            .list => |l| {
                try stdoutIndent(writer, indent_level);
                try writer.print("Type: list of:\n", .{});
                try l.underlying.writeTo(writer, indent_level + 1);
            },
        }
    }

    pub fn fmtTo(_: *Type, _: anytype, _: usize) anyerror!void {}
};

// === Parameter ===

pub const Parameter = struct {
    name: []const u8,
    type: *Type,

    pub fn toString(self: *Parameter, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try self.writeTo(writer, 0);
        return buffer.toOwnedSlice();
    }

    pub fn writeTo(self: *Parameter, writer: anytype, indent_level: usize) anyerror!void {
        try stdoutIndent(writer, indent_level);
        try writer.print("Parameter: name = {s}\n", .{self.name});
        try self.type.writeTo(writer, indent_level + 1);
    }

    pub fn fmtTo(self: *Parameter, writer: anytype, indent_level: usize) anyerror!void {
        try canonicalIndent(writer, indent_level);
        try writer.print("{s}", .{self.name});
    }
};

fn stdoutIndent(writer: anytype, level: usize) !void {
    for (0..level) |_| {
        try writer.writeAll("  ");
    }
}

fn canonicalIndent(writer: anytype, level: usize) !void {
    for (0..level) |_| {
        try writer.writeAll("    ");
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
