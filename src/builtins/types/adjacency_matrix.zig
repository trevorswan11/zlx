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

const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

const AdjacencyMatrix = @import("dsa").AdjacencyMatrix(Value);
pub const AdjacencyMatrixInstance = struct {
    matrix: AdjacencyMatrix,
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
    const size = (try expectNumberArgs(args, env, 1, "adj_matrix", "ctor", "size"))[0];

    const matrix = try AdjacencyMatrix.init(env.allocator, @intFromFloat(size));
    const wrapped = try env.allocator.create(AdjacencyMatrixInstance);
    wrapped.* = .{
        .matrix = matrix,
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

    const parts = try builtins.expectNumberArgs(args, env, 2, "adj_matrix", "add_edge", "from_id, to_id");
    const from = parts[0];
    const to = parts[1];

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from);
    const j: usize = @intFromFloat(to);
    if (i >= inst.matrix.size or j >= inst.matrix.size) {
        try writer_err.print("adj_matrix.add_edge(val_from, val_to): Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, inst.matrix.size });
        return error.IndexOutOfBounds;
    }

    try inst.matrix.addEdge(i, j);
    return .nil;
}

fn adjMatrixRemoveEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    const parts = try builtins.expectNumberArgs(args, env, 2, "adj_matrix", "remove_edge", "from_id, to_id");
    const from = parts[0];
    const to = parts[1];

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from);
    const j: usize = @intFromFloat(to);
    if (i >= inst.matrix.size or j >= inst.matrix.size) {
        try writer_err.print("adj_matrix.remove_edge(val_from, val_to): Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, args.len });
        return error.IndexOutOfBounds;
    }

    try inst.matrix.removeEdge(i, j);
    return .nil;
}

fn adjMatrixContainsEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    const parts = try builtins.expectNumberArgs(args, env, 2, "adj_matrix", "contains_edge", "id");
    const from = parts[0];
    const to = parts[1];

    const inst = try getMatrixInstance(this);
    const i: usize = @intFromFloat(from);
    const j: usize = @intFromFloat(to);
    if (i >= inst.matrix.size or j >= inst.matrix.size) {
        try writer_err.print("adj_matrix.contains_edge(val_from, val_to): Indices ({d}, {d}) out of bounds for matrix size {d}\n", .{ i, j, inst.matrix.size });
        return error.IndexOutOfBounds;
    }

    return .{
        .boolean = try inst.matrix.containsEdge(i, j),
    };
}

fn adjMatrixSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "adj_matrix", "size", "");
    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.matrix.size),
    };
}

fn adjMatrixEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "adj_matrix", "empty", "");
    const inst = try getMatrixInstance(this);
    for (inst.matrix.matrix) |row| {
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

fn adjMatrixClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "adj_matrix", "clear", "");
    const inst = try getMatrixInstance(this);
    for (inst.matrix.matrix) |row| {
        for (row) |*entry| {
            entry.flag = false;
        }
    }
    return .nil;
}

fn adjMatrixEdges(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "adj_matrix", "edges", "");
    const inst = try getMatrixInstance(this);
    return .{
        .number = @floatFromInt(inst.matrix.edge_count),
    };
}

fn adjMatrixStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "adj_matrix", "str", "");
    const inst = try getMatrixInstance(this);
    return .{
        .string = try inst.matrix.toString(),
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
