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

const Array = @import("dsa").Array(Value);
const HashMap = @import("dsa").HashMap(Value, Array, interpreter.ValueContext);

pub const AdjacencyListInstance = struct {
    graph: AdjacencyList,
};

const AdjacencyList = @This().GraphType;
const GraphType = @import("dsa").AdjacencyList(Value, interpreter.ValueContext);

fn getGraphInstance(this: *Value) !*AdjacencyListInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var ADJ_LIST_METHODS: std.StringHashMap(StdMethod) = undefined;
var ADJ_LIST_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    ADJ_LIST_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try ADJ_LIST_METHODS.put("add_edge", adjListAddEdge);
    try ADJ_LIST_METHODS.put("get_neighbors", adjListGetNeighbors);
    try ADJ_LIST_METHODS.put("contains", adjListContains);
    try ADJ_LIST_METHODS.put("clear", adjListClear);
    try ADJ_LIST_METHODS.put("size", adjListSize);
    try ADJ_LIST_METHODS.put("empty", adjListEmpty);
    try ADJ_LIST_METHODS.put("str", adjListStr);

    ADJ_LIST_TYPE = .{
        .std_struct = .{
            .name = "adjacency_list",
            .constructor = adjListConstructor,
            .methods = ADJ_LIST_METHODS,
        },
    };

    return ADJ_LIST_TYPE;
}

fn adjListConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const graph = GraphType.init(allocator);
    const wrapped = try allocator.create(AdjacencyListInstance);
    wrapped.* = .{
        .graph = graph,
    };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "adjacency_list",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = ADJ_LIST_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn adjListAddEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("adj_list.add_edge(val_from, val_to) expects 2 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const inst = try getGraphInstance(this);
    try inst.graph.addEdge(from, to);
    return .nil;
}

fn adjListGetNeighbors(allocator: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("adj_list.get_neighbors(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const node = try interpreter.evalExpr(args[0], env);
    const inst = try getGraphInstance(this);
    const neighbors = inst.graph.getNeighbors(node);
    if (neighbors) |list| {
        var mut_list = list;
        const list_slice = try mut_list.toSlice();
        var array_list = std.ArrayList(Value).init(allocator);
        try array_list.appendSlice(list_slice);
        return .{
            .array = array_list,
        };
    } else {
        return .nil;
    }
}

fn adjListContains(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("adj_list.contains(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const node = try interpreter.evalExpr(args[0], env);
    const inst = try getGraphInstance(this);
    return .{
        .boolean = inst.graph.containsNode(node),
    };
}

fn adjListClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    inst.graph.clear();
    return .nil;
}

fn adjListSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    return .{
        .number = @floatFromInt(inst.graph.size()),
    };
}

fn adjListEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    return .{
        .boolean = inst.graph.size() == 0,
    };
}

fn adjListStr(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    return .{
        .string = try toString(inst.graph),
    };
}

pub fn toString(adj_list: AdjacencyList) ![]const u8 {
    var buffer = std.ArrayList(u8).init(adj_list.allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    var it = adj_list.map.map.iterator();
    while (it.next()) |entry| {
        try writer.print("{s}: ", .{try entry.key_ptr.*.toString(adj_list.allocator)});
        for (entry.value_ptr.*.arr[0..entry.value_ptr.*.len]) |neighbor| {
            try writer.print("{s} ", .{try neighbor.toString(adj_list.allocator)});
        }
        try writer.print("\n", .{});
    }
    _ = buffer.pop();

    return try buffer.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "adjacency_list_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import adjacency_list;
        \\let g = new adjacency_list();
        \\g.add_edge(1, 2);
        \\g.add_edge(1, 3);
        \\g.add_edge(2, 4);
        \\
        \\let n1 = g.get_neighbors(1);
        \\let n2 = g.get_neighbors(2);
        \\let has1 = g.contains(1);
        \\let has9 = g.contains(9);
        \\let count = g.size();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const n1 = try env.get("n1");
    const n2 = try env.get("n2");
    const has1 = try env.get("has1");
    const has9 = try env.get("has9");
    const count = try env.get("count");

    try testing.expect(n1 == .array);
    try testing.expect(n2 == .array);
    try testing.expect(has1 == .boolean);
    try testing.expect(has9 == .boolean);
    try testing.expect(count == .number);

    try testing.expect(has1.boolean);
    try testing.expect(!has9.boolean);
    try testing.expectEqual(@as(f64, 2), count.number);
}
