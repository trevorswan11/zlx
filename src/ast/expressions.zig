const ast = @import("ast.zig");
const tokens = @import("../lexer/token.zig");

// --- Literals ---

pub const NumberExpr = struct {
    value: f64,

    pub fn expr(self: NumberExpr) void {
        _ = self;
    }
};

pub const StringExpr = struct {
    value: []const u8,

    pub fn expr(self: StringExpr) void {
        _ = self;
    }
};

pub const SymbolExpr = struct {
    value: []const u8,
    
    pub fn expr(self: SymbolExpr) void {
        _ = self;
    }
};

// --- Complex ---

pub const BinaryExpr = struct {
    left: ast.Expr,
    operator: tokens.Token,
    right: ast.Expr,

    pub fn expr(self: BinaryExpr) void {
        _ = self;
    }
};

// --- Prefix Expression ---

pub const PrefixExpr = struct {
    operator: tokens.Token,
    right: ast.Expr,

    pub fn expr(self: PrefixExpr) void {
        _ = self;
    }
};

// --- Assignment Expression ---

pub const AssignmentExpr = struct {
    assignee: ast.Expr,
    assigned_value: ast.Expr,

    pub fn expr(self: AssignmentExpr) void {
        _ = self;
    }
};

// --- Member Expression ---

pub const MemberExpr = struct {
    member: ast.Expr,
    property: []const u8,

    pub fn expr(self: MemberExpr) void {
        _ = self;
    }
};

// --- Call Expression ---

pub const CallExpr = struct {
    method: ast.Expr,
    arguments: []ast.Expr,

    pub fn expr(self: CallExpr) void {
        _ = self;
    }
};

// --- Computed Expression ---

pub const ComputedExpr = struct {
    member: ast.Expr,
    property: ast.Expr,

    pub fn expr(self: ComputedExpr) void {
        _ = self;
    }
};

// --- Range Expression ---

pub const RangeExpr = struct {
    lower: ast.Expr,
    upper: ast.Expr,

    pub fn expr(self: RangeExpr) void {
        _ = self;
    }
};

// --- Function Expression ---

pub const FunctionExpr = struct {
    parameters: []ast.Parameter,
    body: []ast.Stmt,
    return_type: ast.Type,

    pub fn expr(self: FunctionExpr) void {
        _ = self;
    }
};

// --- Array Literal ---

pub const ArrayLiteral = struct {
    contents: []ast.Expr,

    pub fn expr(self: ArrayLiteral) void {
        _ = self;
    }
};

// --- New Expression ---

pub const NewExpr = struct {
    instantiation: CallExpr,

    pub fn expr(self: NewExpr) void {
        _ = self;
    }
};
