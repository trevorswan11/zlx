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

const Treap = @import("dsa").Treap(Value, Value.less, Value.eql);
pub const TreapInstance = struct {
    treap: Treap,
};

fn getTreapInstance(this: *Value) !*TreapInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var TREAP_METHODS: std.StringHashMap(StdMethod) = undefined;
var TREAP_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    TREAP_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try TREAP_METHODS.put("insert", treapInsert);
    try TREAP_METHODS.put("contains", treapContains);
    try TREAP_METHODS.put("size", treapSize);
    try TREAP_METHODS.put("empty", treapEmpty);
    try TREAP_METHODS.put("height", treapHeight);
    try TREAP_METHODS.put("clear", treapClear);
    try TREAP_METHODS.put("min", treapMin);
    try TREAP_METHODS.put("max", treapMax);
    try TREAP_METHODS.put("remove", treapRemove);
    try TREAP_METHODS.put("items", treapItems);
    try TREAP_METHODS.put("str", treapStr);

    TREAP_TYPE = .{
        .std_struct = .{
            .name = "treap",
            .constructor = treapConstructor,
            .methods = TREAP_METHODS,
        },
    };

    return TREAP_TYPE;
}

fn treapConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "ctor", "");

    const treap = Treap.init(env.allocator);
    const wrapped = try env.allocator.create(TreapInstance);
    wrapped.* = .{
        .treap = treap,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "treap",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = TREAP_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn treapInsert(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "treap", "insert", "value"))[0];
    const inst = try getTreapInstance(this);
    try inst.treap.insert(val);
    return .nil;
}

fn treapContains(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "treap", "contains", "value"))[0];
    const inst = try getTreapInstance(this);
    return .{
        .boolean = inst.treap.contains(val),
    };
}

fn treapRemove(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "treap", "remove", "value"))[0];
    const inst = try getTreapInstance(this);
    try inst.treap.remove(val);
    return .nil;
}

fn treapSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "size", "");
    const inst = try getTreapInstance(this);
    return .{
        .number = @floatFromInt(inst.treap.size()),
    };
}

fn treapEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "empty", "");
    const inst = try getTreapInstance(this);
    return .{
        .boolean = inst.treap.size() == 0,
    };
}

fn treapHeight(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "height", "");
    const inst = try getTreapInstance(this);
    return .{
        .number = @floatFromInt(inst.treap.height()),
    };
}

fn treapMin(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "min", "");
    const inst = try getTreapInstance(this);
    return inst.treap.findMin() orelse .nil;
}

fn treapMax(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "max", "");
    const inst = try getTreapInstance(this);
    return inst.treap.findMax() orelse .nil;
}

fn treapClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "clear", "");
    const inst = try getTreapInstance(this);
    inst.treap.clear();
    return .nil;
}

fn preorderList(allocator: std.mem.Allocator, t: Treap) !std.ArrayList(Value) {
    var list = std.ArrayList(Value).init(allocator);
    try preorderListImpl(t, t.root, &list);
    return list;
}

fn preorderListImpl(t: Treap, node: ?*Treap.Node, list: *std.ArrayList(Value)) !void {
    if (node) |n| {
        try list.append(n.key);
        try preorderListImpl(t, n.left, list);
        try preorderListImpl(t, n.right, list);
    }
}

pub fn treapItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "items", "");
    const inst = try getTreapInstance(this);
    return .{
        .array = try preorderList(env.allocator, inst.treap),
    };
}

fn treapStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "treap", "str", "");
    const inst = try getTreapInstance(this);
    return .{
        .string = try toString(inst.treap),
    };
}

fn preorderWriter(t: Treap) ![]const u8 {
    var buffer = std.ArrayList(u8).init(t.allocator);
    defer buffer.deinit();
    const writer = buffer.writer().any();
    try preorderWriterImpl(t, t.root, writer);
    _ = buffer.pop();
    return buffer.toOwnedSlice();
}

fn preorderWriterImpl(t: Treap, node: ?*Treap.Node, writer: std.io.AnyWriter) !void {
    if (node) |n| {
        try writer.print("key: {s}, priority: {d}", .{ try n.key.toString(t.allocator), n.priority });
        try writer.print("\n", .{});
        try preorderWriterImpl(t, n.left, writer);
        try preorderWriterImpl(t, n.right, writer);
    }
}

pub fn toString(self: Treap) ![]const u8 {
    return try preorderWriter(self);
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "treap_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import treap;
        \\let t = new treap();
        \\t.insert(5);
        \\t.insert(3);
        \\t.insert(7);
        \\t.insert(2);
        \\t.insert(6);
        \\let c1 = t.contains(5);
        \\let c2 = t.contains(9);
        \\let s = t.size();
        \\let h = t.height();
        \\let mn = t.min();
        \\let mx = t.max();
        \\t.remove(5);
        \\let c3 = t.contains(5);
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const c1 = try env.get("c1");
    const c2 = try env.get("c2");
    const c3 = try env.get("c3");
    const s = try env.get("s");
    const h = try env.get("h");
    const mn = try env.get("mn");
    const mx = try env.get("mx");

    try testing.expect(c1.boolean);
    try testing.expect(!c2.boolean);
    try testing.expect(!c3.boolean);
    try testing.expect(s.number >= 5);
    try testing.expect(h.number >= 2);
    try testing.expect(mn.number <= mx.number);
}
