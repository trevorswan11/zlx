pub fn Expr(comptime T: type) type {
    return struct {
        pub fn expr(self: T) void {
            _ = self;
        }
    };
}

pub fn Stmt(comptime T: type) type {
    return struct {
        pub fn stmt(self: T) void {
            _ = self;
        }
    };
}

pub fn Type(comptime T: type) type {
    return struct {
        pub fn _type(self: T) void {
            _ = self;
        }
    };
}

pub fn Parameter(comptime T: type) type {
    return struct {
        name: []const u8,
        param_type: Type(T),
    };
}

pub fn expectExpr(comptime T: type, value: anytype) T {
    comptime assertIsExpr(T);
    return @as(T, value);
}

pub fn expectStmt(comptime T: type, value: anytype) T {
    comptime assertIsStmt(T);
    return @as(T, value);
}

pub fn ExpectType(comptime T: type, value: anytype) T {
    comptime assertIsType(T);
    return @as(T, value);
}

fn assertIsExpr(comptime T: type) void {
    if (!@hasDecl(T, "expr")) {
        @compileError("Type does not implement Expr interface");
    }
}

fn assertIsStmt(comptime T: type) void {
    if (!@hasDecl(T, "stmt")) {
        @compileError("Type does not implement Stmt interface");
    }
}

fn assertIsType(comptime T: type) void {
    if (!@hasDecl(T, "_type")) {
        @compileError("Type does not implement Type interface");
    }
}