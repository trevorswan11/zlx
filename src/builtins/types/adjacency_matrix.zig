const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const StdMethod = builtins.StdMethod;
const StdCtor = builtins.StdCtor;

pub const AdjacencyMatrixInstance = struct {
    matrix: [][]Node,
    size: usize,
    edge_count: usize,
};

const Node = struct {
    flag: bool,
    weight: ?f64 = null,
};

fn getMatrixInstance(this: *Value) !*AdjacencyMatrixInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var ADJ_MATRIX_METHODS: std.StringHashMap(StdMethod) = undefined;
var ADJ_MATRIX_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    ADJ_MATRIX_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try ADJ_MATRIX_METHODS.put("add_edge", adjMatrixAddEdge);
    try ADJ_MATRIX_METHODS.put("remove_edge", adjMatrixRemoveEdge);
    try ADJ_MATRIX_METHODS.put("add_weighted_edge", adjMatrixAddWeightEdge);
    try ADJ_MATRIX_METHODS.put("get_weight", adjMatrixGetWeight);
    try ADJ_MATRIX_METHODS.put("contains_edge", adjMatrixContainsEdge);
    try ADJ_MATRIX_METHODS.put("size", adjMatrixSize);
    try ADJ_MATRIX_METHODS.put("empty", adjMatrixEmpty);
    try ADJ_MATRIX_METHODS.put("edges", adjMatrixEdges);
    try ADJ_MATRIX_METHODS.put("clear", adjMatrixClear);
    try ADJ_MATRIX_METHODS.put("str", adjMatrixStr);

    ADJ_MATRIX_TYPE = .{
        .std_struct = .{
            .name = "adjacency_matrix",
            .constructor = adjMatrixConstructor,
            .methods = ADJ_MATRIX_METHODS,
        },
    };

    return ADJ_MATRIX_TYPE;
}

fn adjMatrixConstructor(args: []const *ast.Expr, env: *Environment) !Value {
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
    const outer = try env.allocator.alloc([]Node, size);
    for (outer) |*row| {
        row.* = try env.allocator.alloc(Node, size);
        for (0..size) |i| {
            row.*[i] = Node{
                .flag = false,
            };
        }
    }

    const wrapped = try env.allocator.create(AdjacencyMatrixInstance);
    wrapped.* = .{
        .matrix = outer,
        .size = size,
        .edge_count = 0,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "adjacency_matrix",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = ADJ_MATRIX_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn adjMatrixAddEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("adj_matrix.add_edge(val_from, val_to) expects 2 arguments but got {d}\n", .{args.len});
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

fn adjMatrixAddWeightEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("adj_matrix.add_weight_edge(from, to, weight) expects 3 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const weight = try interpreter.evalExpr(args[2], env);

    if (from != .number or to != .number or weight != .number) {
        try writer_err.print("adj_matrix.add_weight_edge(from, to, weight) expects all number arguments.\n", .{});
        return error.TypeMismatch;
    }

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from.number);
    const j: usize = @intFromFloat(to.number);

    if (i >= inst.size or j >= inst.size) {
        try writer_err.print("adj_matrix.add_weight_edge: Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, inst.size });
        return error.IndexOutOfBounds;
    }

    if (!inst.matrix[i][j].flag) {
        inst.matrix[i][j].flag = true;
        inst.edge_count += 1;
    }
    inst.matrix[i][j].weight = weight.number;

    return .nil;
}

fn adjMatrixGetWeight(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("adj_matrix.get_weight(from, to) expects 2 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);

    if (from != .number or to != .number) {
        try writer_err.print("adj_matrix.get_weight(from, to) expects two number arguments.\n", .{});
        return error.TypeMismatch;
    }

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from.number);
    const j: usize = @intFromFloat(to.number);

    if (i >= inst.size or j >= inst.size) {
        try writer_err.print("adj_matrix.get_weight: Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, inst.size });
        return error.IndexOutOfBounds;
    }

    const node = inst.matrix[i][j];
    if (!node.flag) {
        return .nil;
    }

    return if (node.weight) |w| .{
        .number = w,
    } else .{
        .number = 1.0,
    };
}

fn adjMatrixRemoveEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
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

fn adjMatrixContainsEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
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

fn adjMatrixSize(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("adjacency_matrix.size() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.size),
    };
}

fn adjMatrixEmpty(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("adjacency_matrix.empty() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    for (inst.matrix) |row| {
        for (row) |entry| {
            if (entry.flag) {
                return .{
                    .boolean = false,
                };
            }
        }
    }
    return .{
        .boolean = true,
    };
}

fn adjMatrixClear(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("adjacency_matrix.clear() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    for (inst.matrix) |row| {
        for (row) |*entry| {
            entry.flag = false;
        }
    }
    return .nil;
}

fn adjMatrixEdges(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("adjacency_matrix.edges() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.edge_count),
    };
}

fn adjMatrixStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("adjacency_matrix.str() expects 0 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getMatrixInstance(this);
    return .{
        .string = try toString(env.allocator, inst),
    };
}

pub fn toString(allocator: std.mem.Allocator, adj_matrix: *AdjacencyMatrixInstance) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    for (0..adj_matrix.size) |i| {
        for (0..adj_matrix.size) |j| {
            const node = adj_matrix.matrix[i][j];
            if (node.flag) {
                if (node.weight) |w| {
                    try writer.print("{d:.1} ", .{w});
                } else {
                    try writer.print("1 ", .{});
                }
            } else {
                try writer.print("0 ", .{});
            }
        }
        try writer.print("\n", .{});
    }
    _ = buffer.pop();

    return try buffer.toOwnedSlice();
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
        \\m.add_weighted_edge(2, 3, 3.14);
        \\let w = m.get_weight(2, 3);
        \\let none = m.get_weight(3, 2);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const has01 = try env.get("has01");
    const has12 = try env.get("has12");
    const s = try env.get("s");
    const e = try env.get("e");
    const w = try env.get("w");
    const none = try env.get("none");

    try testing.expect(w == .number);
    try testing.expectEqual(@as(f64, 3.14), w.number);
    try testing.expect(none == .nil);

    try testing.expect(has01 == .boolean);
    try testing.expect(has12 == .boolean);
    try testing.expect(s == .number);
    try testing.expect(e == .number);

    try testing.expect(has01.boolean);
    try testing.expect(!has12.boolean);
    try testing.expectEqual(@as(f64, 4), s.number);
    try testing.expectEqual(@as(f64, 1), e.number);
}
