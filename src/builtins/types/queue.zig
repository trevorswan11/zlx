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

const Queue = @import("dsa").Queue(Value);

pub const QueueInstance = struct {
    queue: Queue,
};

fn getQueueInstance(this: *Value) !*QueueInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var QUEUE_METHODS: std.StringHashMap(StdMethod) = undefined;
var QUEUE_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    QUEUE_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try QUEUE_METHODS.put("push", queuePush);
    try QUEUE_METHODS.put("poll", queuePoll);
    try QUEUE_METHODS.put("peek", queuePeek);

    QUEUE_TYPE = .{
        .std_struct = .{
            .name = "queue",
            .constructor = queueConstructor,
            .methods = QUEUE_METHODS,
        },
    };

    return QUEUE_TYPE;
}

fn queueConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const queue = try Queue.init(allocator);
    const wrapped = try allocator.create(QueueInstance);
    wrapped.* = .{ .queue = queue };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "queue",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = QUEUE_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn queuePush(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("queue.push(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const value = try eval.evalExpr(args[0], env);
    const inst = try getQueueInstance(this);
    try inst.queue.push(value);
    return .nil;
}

fn queuePoll(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getQueueInstance(this);
    const result = inst.queue.poll();
    return result orelse .nil;
}

fn queuePeek(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getQueueInstance(this);
    const result = inst.queue.peek();
    return result orelse .nil;
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "queue_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import queue;
        \\let q = new queue();
        \\q.push(1);
        \\q.push(2);
        \\q.push(3);
        \\let a = q.peek();
        \\let b = q.poll();
        \\let c = q.poll();
        \\let d = q.poll();
        \\let e = q.poll();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const a = try env.get("a");
    const b = try env.get("b");
    const c = try env.get("c");
    const d = try env.get("d");
    const e = try env.get("e");

    try testing.expectEqual(@as(f64, 1), a.number);
    try testing.expectEqual(@as(f64, 1), b.number);
    try testing.expectEqual(@as(f64, 2), c.number);
    try testing.expectEqual(@as(f64, 3), d.number);
    try testing.expectEqual(Value.nil, e);
}
