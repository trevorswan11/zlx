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

const Array = @import("dsa").Array(Value);
const Queue = @import("dsa").Queue(Value);
const HashSet = @import("dsa").HashSet(Value, interpreter.ValueContext);
const AdjacencyList = @import("dsa").AdjacencyList(Value, interpreter.ValueContext);

pub const GraphInstance = struct {
    graph: AdjacencyList,
};

fn getGraphInstance(this: *Value) !*GraphInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var GRAPH_METHODS: std.StringHashMap(StdMethod) = undefined;
var GRAPH_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    GRAPH_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try GRAPH_METHODS.put("add_edge", graphAddEdge);
    try GRAPH_METHODS.put("has_node", graphHasNode);
    try GRAPH_METHODS.put("has_edge", graphHasEdge);
    try GRAPH_METHODS.put("clear", graphClear);
    try GRAPH_METHODS.put("str", graphStr);

    GRAPH_TYPE = .{
        .std_struct = .{
            .name = "graph",
            .constructor = graphConstructor,
            .methods = GRAPH_METHODS,
        },
    };

    return GRAPH_TYPE;
}

fn graphConstructor(_: []const *ast.Expr, env: *Environment) !Value {
    const graph = AdjacencyList.init(env.allocator);
    const wrapped = try env.allocator.create(GraphInstance);
    wrapped.* = .{
        .graph = graph,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "graph",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = GRAPH_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn graphAddEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("graph.add_edge(val_from, val_to) expects 2 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const inst = try getGraphInstance(this);
    try inst.graph.put(from);
    try inst.graph.put(to);
    try inst.graph.addEdge(from, to);
    return .nil;
}

fn graphHasNode(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("graph.has_node(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const id = try interpreter.evalExpr(args[0], env);
    const inst = try getGraphInstance(this);
    return .{
        .boolean = inst.graph.containsNode(id),
    };
}

fn graphHasEdge(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("graph.has_edge(val_from, val_to) expects 2 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const inst = try getGraphInstance(this);

    if (inst.graph.getNeighbors(from)) |list| {
        for (list.arr[0..list.len]) |v| {
            if (v.eql(to)) return .{
                .boolean = true,
            };
        }
    }
    return .{
        .boolean = false,
    };
}

fn graphClear(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    inst.graph.clear();
    return .nil;
}

fn graphStr(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    const strFn = @import("adjacency_list.zig").toString;
    return .{
        .string = try strFn(inst.graph),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "graph_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import graph;
        \\let g = new graph();
        \\g.add_edge("a", "b");
        \\g.add_edge("a", "c");
        \\g.add_edge("b", "d");
        \\
        \\let has1 = g.has_node("a");
        \\let has2 = g.has_node("z");
        \\let edge1 = g.has_edge("a", "b");
        \\let edge2 = g.has_edge("b", "a");
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const has1 = try env.get("has1");
    const has2 = try env.get("has2");
    const edge1 = try env.get("edge1");
    const edge2 = try env.get("edge2");

    try testing.expect(has1 == .boolean);
    try testing.expect(has2 == .boolean);
    try testing.expect(edge1 == .boolean);
    try testing.expect(edge2 == .boolean);

    try testing.expect(has1.boolean);
    try testing.expect(!has2.boolean);
    try testing.expect(edge1.boolean);
    try testing.expect(!edge2.boolean);
}
