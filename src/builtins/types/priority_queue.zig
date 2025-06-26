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

pub const PriorityQueueInstance = struct {
    array: Array,
    max_at_top: bool,
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
        try writer_err.print("heap(max_at_top) expects 0 or 1 arguments but got {d}\n", .{args.len});
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
        try writer_err.print("heap(max_at_top) expects a boolean argument but got a(n) {s}\n", .{@tagName(max)});
        return error.TypeMismatch;
    }

    const arr = try Array.init(env.allocator, 8);
    const wrapped = try env.allocator.create(PriorityQueueInstance);
    wrapped.* = .{
        .array = arr,
        .max_at_top = max.boolean,
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

fn compare(inst: *PriorityQueueInstance, a: Value, b: Value) !bool {
    const ord = a.compare(b);
    return if (inst.max_at_top) ord == .gt else ord == .lt;
}

fn siftUp(inst: *PriorityQueueInstance) !void {
    var i = inst.array.len - 1;
    while (i > 0) {
        const parent = (i - 1) / 2;
        const a = try inst.array.get(parent);
        const b = try inst.array.get(i);
        if (!try compare(inst, b, a)) {
            break;
        }
        try inst.array.swap(i, parent);
        i = parent;
    }
}

fn siftDown(inst: *PriorityQueueInstance) !void {
    var i: usize = 0;
    while (true) {
        var selected = i;
        const left = 2 * i + 1;
        const right = 2 * i + 2;

        if (left < inst.array.len) {
            const a = try inst.array.get(selected);
            const b = try inst.array.get(left);
            if (try compare(inst, b, a)) {
                selected = left;
            }
        }

        if (right < inst.array.len) {
            const a = try inst.array.get(selected);
            const b = try inst.array.get(right);
            if (try compare(inst, b, a)) {
                selected = right;
            }
        }

        if (selected == i) {
            break;
        }
        try inst.array.swap(i, selected);
        i = selected;
    }
}

fn pqInsert(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("heap.insert(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const value = try eval.evalExpr(args[0], env);
    const inst = try getPriorityQueueInstance(this);
    try inst.array.push(value);
    try siftUp(inst);
    return .nil;
}

fn pqPoll(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    if (inst.array.len == 0) {
        return .nil;
    }
    const top = try inst.array.get(0);
    const last = try inst.array.pop();
    if (inst.array.len > 0) {
        try inst.array.set(0, last);
        try siftDown(inst);
    }
    return top;
}

fn pqPeek(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    return if (inst.array.len == 0) .nil else try inst.array.get(0);
}

fn pqSize(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    return .{
        .number = @floatFromInt(inst.array.len),
    };
}

fn pqEmpty(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    return .{
        .boolean = inst.array.len == 0,
    };
}

fn pqClear(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    inst.array.clear();
    return .nil;
}

pub fn pqItems(this: *Value, _: []const *ast.Expr, env: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    for (inst.array.arr[0..inst.array.len]) |val| {
        try vals.append(val);
    }

    return .{
        .array = vals,
    };
}

fn pqStr(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getPriorityQueueInstance(this);
    const strFn = @import("array_list.zig").toString;
    return .{
        .string = try strFn(inst.array),
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
