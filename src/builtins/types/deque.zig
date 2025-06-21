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

const List = @import("dsa").List(Value);

pub const DequeInstance = struct {
    list: List,
};

fn getDequeInstance(this: *Value) !*DequeInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var DEQUE_METHODS: std.StringHashMap(StdMethod) = undefined;
var DEQUE_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    DEQUE_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try DEQUE_METHODS.put("push_head", dequePushHead);
    try DEQUE_METHODS.put("push_tail", dequePushTail);
    try DEQUE_METHODS.put("pop_head", dequePopHead);
    try DEQUE_METHODS.put("pop_tail", dequePopTail);
    try DEQUE_METHODS.put("peek_head", dequePeekHead);
    try DEQUE_METHODS.put("peek_tail", dequePeekTail);

    DEQUE_TYPE = .{
        .std_struct = .{
            .name = "deque",
            .constructor = dequeConstructor,
            .methods = DEQUE_METHODS,
        },
    };

    return DEQUE_TYPE;
}

fn dequeConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const list = try List.init(allocator);
    const wrapped = try allocator.create(DequeInstance);
    wrapped.* = .{
        .list = list,
    };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "deque",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = DEQUE_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn dequePushHead(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("deque.push_head(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const deque = try getDequeInstance(this);
    try deque.list.prepend(val);
    return .nil;
}

fn dequePushTail(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("deque.push_tail(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const deque = try getDequeInstance(this);
    try deque.list.append(val);
    return .nil;
}

fn dequePopHead(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const deque = try getDequeInstance(this);
    return deque.list.popHead() orelse .nil;
}

fn dequePopTail(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const deque = try getDequeInstance(this);
    return deque.list.popTail() orelse .nil;
}

fn dequePeekHead(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const deque = try getDequeInstance(this);
    return deque.list.peekHead() orelse .nil;
}

fn dequePeekTail(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const deque = try getDequeInstance(this);
    return deque.list.peekTail() orelse .nil;
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "deque_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import deque;
        \\let d = new deque();
        \\d.push_head(2);
        \\d.push_tail(3);
        \\d.push_head(1);
        \\d.push_tail(4);
        \\
        \\let h1 = d.peek_head();
        \\let t1 = d.peek_tail();
        \\let pop1 = d.pop_head();
        \\let pop2 = d.pop_tail();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const h1 = try env.get("h1");
    const t1 = try env.get("t1");
    const pop1 = try env.get("pop1");
    const pop2 = try env.get("pop2");

    try testing.expect(h1 == .number);
    try testing.expect(t1 == .number);
    try testing.expect(pop1 == .number);
    try testing.expect(pop2 == .number);

    try testing.expectEqual(@as(f64, 1), pop1.number);
    try testing.expectEqual(@as(f64, 4), pop2.number);
}
