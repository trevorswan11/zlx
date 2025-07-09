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

const Deque = @import("dsa").Deque(Value);
pub const DequeInstance = struct {
    deque: Deque,
};

fn getDequeInstance(this: *Value) !*DequeInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
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
    try DEQUE_METHODS.put("size", dequeSize);
    try DEQUE_METHODS.put("empty", dequeEmpty);
    try DEQUE_METHODS.put("clear", dequeClear);
    try DEQUE_METHODS.put("items", dequeItems);
    try DEQUE_METHODS.put("str", dequeStr);

    DEQUE_TYPE = .{
        .std_struct = .{
            .name = "deque",
            .constructor = dequeConstructor,
            .methods = DEQUE_METHODS,
        },
    };

    return DEQUE_TYPE;
}

fn dequeConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const deque = try Deque.init(env.allocator);
    const wrapped = try env.allocator.create(DequeInstance);
    wrapped.* = .{
        .deque = deque,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "deque",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = DEQUE_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn dequePushHead(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("deque.push_head(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getDequeInstance(this);
    try inst.deque.pushHead(val);
    return .nil;
}

fn dequePushTail(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("deque.push_tail(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getDequeInstance(this);
    try inst.deque.pushTail(val);
    return .nil;
}

fn dequePopHead(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.pop_head() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const deque = try getDequeInstance(this);
    return deque.deque.popHead() orelse .nil;
}

fn dequePopTail(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.pop_tail() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    return inst.deque.popTail() orelse .nil;
}

fn dequePeekHead(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.peek_head() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    return inst.deque.peekHead() orelse .nil;
}

fn dequePeekTail(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.peek_tail() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    return inst.deque.peekTail() orelse .nil;
}

fn dequeClear(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.clear() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    inst.deque.list.clear();
    return .nil;
}

fn dequeEmpty(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.empty() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    return .{
        .boolean = inst.deque.list.empty(),
    };
}

fn dequeSize(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.size() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    return .{
        .number = @floatFromInt(inst.deque.list.len),
    };
}

pub fn dequeItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.items() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    var itr = inst.deque.list.begin();
    while (itr.next()) |val| {
        try vals.append(val.*);
    }

    return .{
        .array = vals,
    };
}

fn dequeStr(this: *Value, args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("deque.str() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const inst = try getDequeInstance(this);
    return .{
        .string = try inst.deque.toString(),
    };
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
