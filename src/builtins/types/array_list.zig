const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const ArrayList = @import("dsa").Array(Value);

const StdMethod = builtins.StdMethod;
const StdCtor = builtins.StdCtor;

pub const ArrayListInstance = struct {
    array: ArrayList,
};

fn getArrayListInstance(this: *Value) !*ArrayListInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var ARRAY_LIST_METHODS: std.StringHashMap(StdMethod) = undefined;
var ARRAY_LIST_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    ARRAY_LIST_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try ARRAY_LIST_METHODS.put("push", arrayListPush);
    try ARRAY_LIST_METHODS.put("insert", arrayListInsert);
    try ARRAY_LIST_METHODS.put("remove", arrayListRemove);
    try ARRAY_LIST_METHODS.put("pop", arrayListPop);
    try ARRAY_LIST_METHODS.put("get", arrayListGet);
    try ARRAY_LIST_METHODS.put("set", arrayListSet);
    try ARRAY_LIST_METHODS.put("clear", arrayListClear);
    try ARRAY_LIST_METHODS.put("empty", arrayListEmpty);
    try ARRAY_LIST_METHODS.put("size", arrayListSize);
    try ARRAY_LIST_METHODS.put("items", arrayListItems);
    try ARRAY_LIST_METHODS.put("str", arrayListStr);

    ARRAY_LIST_TYPE = .{
        .std_struct = .{
            .name = "array_list",
            .constructor = arrayListConstructor,
            .methods = ARRAY_LIST_METHODS,
        },
    };

    return ARRAY_LIST_TYPE;
}

fn arrayListConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const capacity: usize = if (args.len == 1) blk: {
        const val = try interpreter.evalExpr(args[0], env);
        if (val != .number) {
            try writer_err.print("array_list(initial_capacity) expects a number arg but got a(n) {s}\n", .{@tagName(val)});
            return error.TypeMismatch;
        }
        break :blk @intFromFloat(val.number);
    } else 8;

    const array = try ArrayList.init(env.allocator, capacity);
    const wrapped = try env.allocator.create(ArrayListInstance);
    wrapped.* = .{
        .array = array,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "array_list",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = ARRAY_LIST_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn arrayListPush(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("array_list.push(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getArrayListInstance(this);
    try inst.array.push(val);
    return .nil;
}

fn arrayListInsert(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("array_list.insert(index, value) expects 2 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    const value = try interpreter.evalExpr(args[1], env);
    if (index_val != .number) {
        try writer_err.print("array_list.insert(index, value) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getArrayListInstance(this);
    try inst.array.insert(@intFromFloat(index_val.number), value);
    return .nil;
}

fn arrayListRemove(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("array_list.remove(index) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) {
        try writer_err.print("array_list.remove(index) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getArrayListInstance(this);
    return try inst.array.remove(@intFromFloat(index_val.number));
}

fn arrayListPop(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayListInstance(this);
    return try inst.array.pop();
}

fn arrayListGet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("array_list.get(index) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) {
        try writer_err.print("array_list.get(index) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getArrayListInstance(this);
    return try inst.array.get(@intFromFloat(index_val.number));
}

fn arrayListSet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("array_list.set(index, value) expects 2 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    const value = try interpreter.evalExpr(args[1], env);
    if (index_val != .number) {
        try writer_err.print("array_list.set(index, value) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getArrayListInstance(this);
    try inst.array.set(@intFromFloat(index_val.number), value);
    return .nil;
}

fn arrayListClear(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayListInstance(this);
    inst.array.clear();
    return .nil;
}

fn arrayListEmpty(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayListInstance(this);
    return .{
        .boolean = inst.array.empty(),
    };
}

fn arrayListSize(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayListInstance(this);
    return .{
        .number = @floatFromInt(inst.array.len),
    };
}

pub fn arrayListItems(this: *Value, _: []const *ast.Expr, env: *Environment) !Value {
    const inst = try getArrayListInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    for (inst.array.arr[0..inst.array.len]) |val| {
        try vals.append(val);
    }

    return .{
        .array = vals,
    };
}

fn arrayListStr(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayListInstance(this);
    return .{
        .string = try toString(inst.array),
    };
}

pub fn toString(array_list: ArrayList) ![]const u8 {
    var buffer = std.ArrayList(u8).init(array_list.allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    try writer.print("[", .{});
    for (array_list.arr[0..array_list.len]) |value| {
        try writer.print(" {s}", .{try value.toString(array_list.allocator)});
    }
    try writer.print(" ]", .{});

    return try buffer.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "array_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import array_list;
        \\let a = new array_list(5);
        \\a.push("first");
        \\a.push("second");
        \\let removed = a.pop();
        \\let empty = a.empty();
        \\let length = a.size();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const removed = try env.get("removed");
    const empty = try env.get("empty");
    const len = try env.get("length");

    try testing.expect(removed == .string);
    try testing.expectEqualStrings("second", removed.string);
    try testing.expect(empty == .boolean);
    try testing.expect(!empty.boolean);
    try testing.expect(len == .number);
    try testing.expectEqual(@as(f64, 1.0), len.number);
}
