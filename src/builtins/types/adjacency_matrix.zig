const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const StdMethod = Value.StdMethod;
const StdCtor = Value.StdCtor;

pub const AdjacencyMatrixInstance = struct {
    matrix: [][]Node,
    size: usize,
    edge_count: usize,
};

const Node = struct {
    flag: bool,
};

fn getMatrixInstance(this: *Value) !*AdjacencyMatrixInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var ADJ_MATRIX_METHODS: std.StringHashMap(StdMethod) = undefined;
var ADJ_MATRIX_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    ADJ_MATRIX_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try ADJ_MATRIX_METHODS.put("add_edge", adjMatrixAddEdge);
    try ADJ_MATRIX_METHODS.put("remove_edge", adjMatrixRemoveEdge);
    try ADJ_MATRIX_METHODS.put("contains_edge", adjMatrixContainsEdge);
    try ADJ_MATRIX_METHODS.put("size", getSize);
    try ADJ_MATRIX_METHODS.put("edges", getEdgeCount);

    ADJ_MATRIX_TYPE = .{
        .std_struct = .{
            .name = "adjacency_matrix",
            .constructor = adjMatrixConstructor,
            .methods = ADJ_MATRIX_METHODS,
        },
    };

    return ADJ_MATRIX_TYPE;
}

fn adjMatrixConstructor(
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("adj_matrix(size) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const size_val = try interpreter.evalExpr(args[0], env);
    if (size_val != .number) {
        try writer_err.print("adj_matrix(size) expects a number argument but got a(n) {s}\n", .{@tagName(size_val)});
        return error.TypeMismatch;
    }

    const size: usize = @intFromFloat(size_val.number);
    const outer = try allocator.alloc([]Node, size);
    for (outer) |*row| {
        row.* = try allocator.alloc(Node, size);
        for (0..size) |i| {
            row.*[i] = Node{
                .flag = false,
            };
        }
    }

    const wrapped = try allocator.create(AdjacencyMatrixInstance);
    wrapped.* = .{
        .matrix = outer,
        .size = size,
        .edge_count = 0,
    };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "adjacency_matrix",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = ADJ_MATRIX_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn adjMatrixAddEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("adj_matrix.add_edge(val_from, val_to) expects 2 arguments but got a(n) {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    if (from != .number or to != .number) {
        try writer_err.print("adj_matrix.add_edge(val_from, val_to) expects two number arguments but got:\n", .{});
        try writer_err.print("  From: {s}\n", .{@tagName(from)});
        try writer_err.print("  To: {s}\n", .{@tagName(to)});
        return error.TypeMismatch;
    }

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from.number);
    const j: usize = @intFromFloat(to.number);
    if (i >= inst.size or j >= inst.size) {
        try writer_err.print("adj_matrix.add_edge(val_from, val_to): Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, inst.size });
        return error.IndexOutOfBounds;
    }

    if (!inst.matrix[i][j].flag) {
        inst.matrix[i][j].flag = true;
        inst.edge_count += 1;
    }

    return .nil;
}

fn adjMatrixRemoveEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("adj_matrix.remove_edge(val_from, val_to) expects 2 arguments but got a(n) {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    if (from != .number or to != .number) {
        try writer_err.print("adj_matrix.remove_edge(val_from, val_to) expects two number arguments but got:\n", .{});
        try writer_err.print("  From: {s}\n", .{@tagName(from)});
        try writer_err.print("  To: {s}\n", .{@tagName(to)});
        return error.TypeMismatch;
    }

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from.number);
    const j: usize = @intFromFloat(to.number);
    if (i >= inst.size or j >= inst.size) {
        try writer_err.print("adj_matrix.remove_edge(val_from, val_to): Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, args.len });
        return error.IndexOutOfBounds;
    }

    if (inst.matrix[i][j].flag) {
        inst.matrix[i][j].flag = false;
        inst.edge_count -= 1;
    }

    return .nil;
}

fn adjMatrixContainsEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("adj_matrix.contains_edge(val_from, val_to) expects 2 arguments but got a(n) {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    if (from != .number or to != .number) {
        try writer_err.print("adj_matrix.contains_edge(val_from, val_to) expects two number arguments but got:\n", .{});
        try writer_err.print("  From: {s}\n", .{@tagName(from)});
        try writer_err.print("  To: {s}\n", .{@tagName(to)});
        return error.TypeMismatch;
    }

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from.number);
    const j: usize = @intFromFloat(to.number);
    if (i >= inst.size or j >= inst.size) {
        try writer_err.print("adj_matrix.contains_edge(val_from, val_to): Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, inst.size });
        return error.IndexOutOfBounds;
    }

    return .{
        .boolean = inst.matrix[i][j].flag,
    };
}

fn getSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.size),
    };
}

fn getEdgeCount(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.edge_count),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "adjacency_matrix_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import adjacency_matrix;
        \\let m = new adjacency_matrix(4);
        \\m.add_edge(0, 1);
        \\m.add_edge(1, 2);
        \\m.remove_edge(1, 2);
        \\let has01 = m.contains_edge(0, 1);
        \\let has12 = m.contains_edge(1, 2);
        \\let s = m.size();
        \\let e = m.edges();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const has01 = try env.get("has01");
    const has12 = try env.get("has12");
    const s = try env.get("s");
    const e = try env.get("e");

    try testing.expect(has01 == .boolean);
    try testing.expect(has12 == .boolean);
    try testing.expect(s == .number);
    try testing.expect(e == .number);

    try testing.expect(has01.boolean);
    try testing.expect(!has12.boolean);
    try testing.expectEqual(@as(f64, 4), s.number);
    try testing.expectEqual(@as(f64, 1), e.number);
}
