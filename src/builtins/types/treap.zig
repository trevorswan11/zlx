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

const Treap = @import("dsa").Treap(Value, lessThan, eql);
fn lessThan(a: Value, b: Value) bool {
    return a.compare(b) == .lt;
}

fn eql(a: Value, b: Value) bool {
    return a.eql(b);
}

pub const TreapInstance = struct {
    treap: Treap,
};

fn getTreapInstance(this: *Value) !*TreapInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(internal.*.typed_val.value);
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
    try TREAP_METHODS.put("str", treapStr);

    TREAP_TYPE = Value{
        .std_struct = .{
            .name = "Treap",
            .constructor = treapConstructor,
            .methods = TREAP_METHODS,
        },
    };

    return TREAP_TYPE;
}

fn treapConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const treap = Treap.init(allocator);
    const wrapped = try allocator.create(TreapInstance);
    wrapped.* = .{ .treap = treap };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "Treap",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = TREAP_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn treapInsert(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("treap.insert(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    const inst = try getTreapInstance(this);
    try inst.treap.insert(val);
    return .nil;
}

fn treapContains(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("treap.contains(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    const inst = try getTreapInstance(this);
    return .{
        .boolean = inst.treap.contains(val),
    };
}

fn treapRemove(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("treap.remove(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try eval.evalExpr(args[0], env);
    const inst = try getTreapInstance(this);
    try inst.treap.remove(val);
    return .nil;
}

fn treapSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    return .{
        .number = @floatFromInt(inst.treap.size()),
    };
}

fn treapEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    return .{
        .boolean = inst.treap.size() == 0,
    };
}

fn treapHeight(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    return .{
        .number = @floatFromInt(inst.treap.height()),
    };
}

fn treapMin(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    return inst.treap.findMin() orelse .nil;
}

fn treapMax(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    return inst.treap.findMax() orelse .nil;
}

fn treapClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    inst.treap.clear();
    return .nil;
}

fn treapStr(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getTreapInstance(this);
    return .{
        .string = try toString(inst.treap),
    };
}

pub fn preorder(t: Treap) ![]const u8 {
    var buffer = std.ArrayList(u8).init(t.allocator);
    defer buffer.deinit();
    const writer = buffer.writer().any();
    try preorderImpl(t, t.root, writer);
    _ = buffer.pop();
    return buffer.toOwnedSlice();
}

fn preorderImpl(t: Treap, node: ?*Treap.Node, writer: std.io.AnyWriter) !void {
    if (node) |n| {
        try preorderImpl(t, n.left, writer);
        try writer.print("key: {s}, priority: {d}", .{ try n.key.toString(t.allocator), n.priority });
        try writer.print("\n", .{});
        try preorderImpl(t, n.right, writer);
    }
}

pub fn toString(self: Treap) ![]const u8 {
    return try preorder(self);
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
