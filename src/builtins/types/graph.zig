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
const Queue = @import("dsa").Queue(Value);
const HashSet = @import("dsa").HashSet(Value, interpreter.ValueContext);
const AdjacencyList = @import("dsa").AdjacencyList(Value, interpreter.ValueContext);

pub const GraphInstance = struct {
    graph: AdjacencyList,
};

fn getGraphInstance(this: *Value) !*GraphInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var GRAPH_METHODS: std.StringHashMap(StdMethod) = undefined;
var GRAPH_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    GRAPH_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try GRAPH_METHODS.put("addEdge", graphAddEdge);
    try GRAPH_METHODS.put("hasNode", graphHasNode);
    try GRAPH_METHODS.put("hasEdge", graphHasEdge);
    try GRAPH_METHODS.put("clear", graphClear);

    GRAPH_TYPE = Value{
        .std_struct = .{
            .name = "Graph",
            .constructor = graphConstructor,
            .methods = GRAPH_METHODS,
        },
    };

    return GRAPH_TYPE;
}

fn graphConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const graph = AdjacencyList.init(allocator);
    const wrapped = try allocator.create(GraphInstance);
    wrapped.* = .{ .graph = graph };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "Graph",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = GRAPH_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn graphAddEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) return error.ArgumentCountMismatch;
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const inst = try getGraphInstance(this);
    try inst.graph.put(from);
    try inst.graph.put(to);
    try inst.graph.addEdge(from, to);
    return .nil;
}

fn graphHasNode(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const id = try interpreter.evalExpr(args[0], env);
    const inst = try getGraphInstance(this);
    return Value{ .boolean = inst.graph.containsNode(id) };
}

fn graphHasEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) return error.ArgumentCountMismatch;
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const inst = try getGraphInstance(this);

    if (inst.graph.getNeighbors(from)) |list| {
        for (list.arr) |v| {
            if (v.eql(to)) return Value{ .boolean = true };
        }
    }
    return Value{ .boolean = false };
}

fn graphClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    inst.graph.clear();
    return .nil;
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
        \\g.addEdge("a", "b");
        \\g.addEdge("a", "c");
        \\g.addEdge("b", "d");
        \\
        \\let has1 = g.hasNode("a");
        \\let has2 = g.hasNode("z");
        \\let edge1 = g.hasEdge("a", "b");
        \\let edge2 = g.hasEdge("b", "a");
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
