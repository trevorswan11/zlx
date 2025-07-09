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

const ArrayList = @import("dsa").Array(Value);
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

const DEFAULT_CAPACITY: usize = 8;

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
    const capacity: usize = if (args.len == 1) blk: {
        const num = (try builtins.expectNumberArgs(args, env, 1, "array_list", "ctor", "capacity"))[0];
        break :blk @intFromFloat(num);
    } else DEFAULT_CAPACITY;

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
    const val = (try expectValues(args, env, 1, "array_list", "push", "value"))[0];
    const inst = try getArrayListInstance(this);
    try inst.array.push(val);
    return .nil;
}

fn arrayListInsert(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index = (try expectNumberArgs(args[0..1], env, 1, "array_list", "set", "index, value"))[0];
    const value = (try expectValues(args[1..], env, 1, "array_list", "set", "index, value"))[0];

    const inst = try getArrayListInstance(this);
    try inst.array.insert(@intFromFloat(index), value);
    return .nil;
}

fn arrayListRemove(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index_val = (try builtins.expectNumberArgs(args, env, 1, "array_list", "remove", "index"))[0];
    const inst = try getArrayListInstance(this);
    return try inst.array.remove(@intFromFloat(index_val));
}

fn arrayListPop(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "array_list", "pop", "");
    const inst = try getArrayListInstance(this);
    return try inst.array.pop();
}

fn arrayListGet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index_val = (try builtins.expectNumberArgs(args, env, 1, "array_list", "get", "index"))[0];
    const inst = try getArrayListInstance(this);
    return try inst.array.get(@intFromFloat(index_val));
}

fn arrayListSet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index = (try expectNumberArgs(args[0..1], env, 1, "array_list", "set", "index, value"))[0];
    const value = (try expectValues(args[1..], env, 1, "array_list", "set", "index, value"))[0];

    const inst = try getArrayListInstance(this);
    try inst.array.set(@intFromFloat(index), value);
    return .nil;
}

fn arrayListClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "array_list", "clear", "");
    const inst = try getArrayListInstance(this);
    inst.array.clear();
    return .nil;
}

fn arrayListEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "array_list", "empty", "");
    const inst = try getArrayListInstance(this);
    return .{
        .boolean = inst.array.empty(),
    };
}

fn arrayListSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "array_list", "size", "");
    const inst = try getArrayListInstance(this);
    return .{
        .number = @floatFromInt(inst.array.len),
    };
}

pub fn arrayListItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "array_list", "items", "");
    const inst = try getArrayListInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    for (inst.array.arr[0..inst.array.len]) |val| {
        try vals.append(val);
    }

    return .{
        .array = vals,
    };
}

fn arrayListStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "array_list", "str", "");
    const inst = try getArrayListInstance(this);
    return .{
        .string = try inst.array.toString(),
    };
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
