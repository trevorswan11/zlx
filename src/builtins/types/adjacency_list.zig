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

    return @ptrCast(internal.*.typed_val.value);
}

var ADJ_METHODS: std.StringHashMap(StdMethod) = undefined;
var ADJ_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    ADJ_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try ADJ_METHODS.put("addEdge", addEdge);
    try ADJ_METHODS.put("getNeighbors", getNeighbors);
    try ADJ_METHODS.put("contains", contains);
    try ADJ_METHODS.put("clear", clear);
    try ADJ_METHODS.put("size", size);

    ADJ_TYPE = Value{
        .std_struct = .{
            .name = "AdjacencyList",
            .constructor = adjConstructor,
            .methods = ADJ_METHODS,
        },
    };

    return ADJ_TYPE;
}

fn adjConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const graph = GraphType.init(allocator);
    const wrapped = try allocator.create(AdjacencyListInstance);
    wrapped.* = .{ .graph = graph };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "AdjacencyList",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = ADJ_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn addEdge(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) return error.ArgumentCountMismatch;
    const from = try interpreter.evalExpr(args[0], env);
    const to = try interpreter.evalExpr(args[1], env);
    const inst = try getGraphInstance(this);
    try inst.graph.addEdge(from, to);
    return .nil;
}

fn getNeighbors(allocator: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const node = try interpreter.evalExpr(args[0], env);
    const inst = try getGraphInstance(this);
    const neighbors = inst.graph.getNeighbors(node);
    if (neighbors) |list| {
        var mut_list = list;
        const list_slice = try mut_list.toOwnedSlice();
        var array_list = std.ArrayList(Value).init(allocator);
        try array_list.appendSlice(list_slice);
        return Value{ .array = array_list };
    } else {
        return .nil;
    }
}

fn contains(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const node = try interpreter.evalExpr(args[0], env);
    const inst = try getGraphInstance(this);
    return Value{ .boolean = inst.graph.containsNode(node) };
}

fn clear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    inst.graph.clear();
    return .nil;
}

fn size(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getGraphInstance(this);
    return Value{ .number = @floatFromInt(inst.graph.size()) };
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
        \\g.addEdge(1, 2);
        \\g.addEdge(1, 3);
        \\g.addEdge(2, 4);
        \\
        \\let n1 = g.getNeighbors(1);
        \\let n2 = g.getNeighbors(2);
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
