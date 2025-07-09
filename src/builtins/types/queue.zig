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

const Queue = @import("dsa").Queue(Value);
pub const QueueInstance = struct {
    queue: Queue,
};

fn getQueueInstance(this: *Value) !*QueueInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var QUEUE_METHODS: std.StringHashMap(StdMethod) = undefined;
var QUEUE_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    QUEUE_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try QUEUE_METHODS.put("push", queuePush);
    try QUEUE_METHODS.put("enqueue", queuePush);
    try QUEUE_METHODS.put("poll", queuePoll);
    try QUEUE_METHODS.put("dequeue", queuePoll);
    try QUEUE_METHODS.put("size", queueSize);
    try QUEUE_METHODS.put("empty", queueEmpty);
    try QUEUE_METHODS.put("peek", queuePeek);
    try QUEUE_METHODS.put("clear", queueClear);
    try QUEUE_METHODS.put("items", queueItems);
    try QUEUE_METHODS.put("str", queueStr);

    QUEUE_TYPE = .{
        .std_struct = .{
            .name = "queue",
            .constructor = queueConstructor,
            .methods = QUEUE_METHODS,
        },
    };

    return QUEUE_TYPE;
}

fn queueConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "ctor", "");

    const queue = try Queue.init(env.allocator);
    const wrapped = try env.allocator.create(QueueInstance);
    wrapped.* = .{
        .queue = queue,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "queue",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = QUEUE_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn queuePush(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const value = (try expectValues(args, env, 1, "queue", "push", "value"))[0];
    const inst = try getQueueInstance(this);
    try inst.queue.push(value);
    return .nil;
}

fn queuePoll(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "poll", "");
    const inst = try getQueueInstance(this);
    const result = inst.queue.poll();
    return result orelse .nil;
}

fn queuePeek(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "peek", "");
    const inst = try getQueueInstance(this);
    const result = inst.queue.peek();
    return result orelse .nil;
}

fn queueSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "size", "");
    const inst = try getQueueInstance(this);
    return .{
        .number = @floatFromInt(inst.queue.list.len),
    };
}

fn queueEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "empty", "");
    const inst = try getQueueInstance(this);
    return .{
        .boolean = inst.queue.list.empty(),
    };
}

fn queueClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "clear", "");
    const inst = try getQueueInstance(this);
    inst.queue.list.clear();
    return .nil;
}

pub fn queueItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "items", "");
    const inst = try getQueueInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    var itr = inst.queue.list.begin();
    while (itr.next()) |val| {
        try vals.append(val.*);
    }

    return .{
        .array = vals,
    };
}

fn queueStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "queue", "str", "");
    const inst = try getQueueInstance(this);
    const strFn = @import("list.zig").toString;
    return .{
        .string = try strFn(inst.queue.list),
    };
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
