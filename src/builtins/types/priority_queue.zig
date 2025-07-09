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

const PriorityQueue = @import("dsa").PriorityQueue(Value, Value.less);
pub const PriorityQueueInstance = struct {
    pq: PriorityQueue,
};

fn getPriorityQueueInstance(this: *Value) !*PriorityQueueInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var PRIORITY_QUEUE_METHODS: std.StringHashMap(StdMethod) = undefined;
var PRIORITY_QUEUE_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    PRIORITY_QUEUE_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try PRIORITY_QUEUE_METHODS.put("insert", pqInsert);
    try PRIORITY_QUEUE_METHODS.put("poll", pqPoll);
    try PRIORITY_QUEUE_METHODS.put("peek", pqPeek);
    try PRIORITY_QUEUE_METHODS.put("size", pqSize);
    try PRIORITY_QUEUE_METHODS.put("empty", pqEmpty);
    try PRIORITY_QUEUE_METHODS.put("clear", pqClear);
    try PRIORITY_QUEUE_METHODS.put("items", pqItems);
    try PRIORITY_QUEUE_METHODS.put("str", pqStr);

    PRIORITY_QUEUE_TYPE = .{
        .std_struct = .{
            .name = "heap",
            .constructor = pqConstructor,
            .methods = PRIORITY_QUEUE_METHODS,
        },
    };

    return PRIORITY_QUEUE_TYPE;
}

fn pqConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len > 1) {
        try writer_err.print("heap.ctor(max_at_top): expected 0 or 1 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const max: Value = if (args.len == 1) blk: {
        break :blk try eval.evalExpr(args[0], env);
    } else blk: {
        break :blk .{
            .boolean = true,
        };
    };

    if (max != .boolean) {
        try writer_err.print("heap.ctor(max_at_top): expected a boolean argument but got a(n) {s}\n", .{@tagName(max)});
        return error.TypeMismatch;
    }

    const pq = try PriorityQueue.init(env.allocator, if (max.boolean) .max_at_top else .min_at_top, 8);
    const wrapped = try env.allocator.create(PriorityQueueInstance);
    wrapped.* = .{
        .pq = pq,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "heap",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = PRIORITY_QUEUE_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn pqInsert(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const value = (try expectValues(args, env, 1, "pq", "insert", "value"))[0];
    const inst = try getPriorityQueueInstance(this);
    try inst.pq.insert(value);
    return .nil;
}

fn pqPoll(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "poll", "");
    const inst = try getPriorityQueueInstance(this);
    if (try inst.pq.poll()) |popped| {
        return popped;
    } else {
        return .nil;
    }
}

fn pqPeek(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "peek", "");
    const inst = try getPriorityQueueInstance(this);
    return if (inst.pq.size() == 0) .nil else try inst.pq.peek();
}

fn pqSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "size", "");
    const inst = try getPriorityQueueInstance(this);
    return .{
        .number = @floatFromInt(inst.pq.size()),
    };
}

fn pqEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "empty", "");
    const inst = try getPriorityQueueInstance(this);
    return .{
        .boolean = inst.pq.empty(),
    };
}

fn pqClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "clear", "");
    const inst = try getPriorityQueueInstance(this);
    while (try inst.pq.poll()) |_| {}
    return .nil;
}

pub fn pqItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "items", "");
    const inst = try getPriorityQueueInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    for (0..inst.pq.size()) |idx| {
        try vals.append(try inst.pq.get(idx));
    }

    return .{
        .array = vals,
    };
}

fn pqStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "pq", "str", "");
    const inst = try getPriorityQueueInstance(this);
    return .{
        .string = try inst.pq.toString(),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "priority_queue_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import heap;
        \\let q = new heap(true);
        \\q.insert(10);
        \\q.insert(3);
        \\q.insert(8);
        \\let a = q.poll();
        \\let b = q.poll();
        \\let c = q.poll();
        \\let empty = q.empty();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const a = try env.get("a");
    const b = try env.get("b");
    const c = try env.get("c");
    const empty = try env.get("empty");

    try testing.expectEqual(@as(f64, 10), a.number);
    try testing.expectEqual(@as(f64, 8), b.number);
    try testing.expectEqual(@as(f64, 3), c.number);
    try testing.expect(empty.boolean);
}
