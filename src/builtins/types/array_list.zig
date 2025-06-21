const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;

const ArrayList = @import("dsa").Array(Value); // Replace with actual dsa location

const StdMethod = Value.StdMethod;
const StdCtor = Value.StdCtor;

pub const ArrayListInstance = struct {
    array: ArrayList,
};

fn getArrayInstance(this: *Value) !*ArrayListInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var ARRAY_METHODS: std.StringHashMap(StdMethod) = undefined;
var ARRAY_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    ARRAY_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try ARRAY_METHODS.put("push", arrayPush);
    try ARRAY_METHODS.put("insert", arrayInsert);
    try ARRAY_METHODS.put("remove", arrayRemove);
    try ARRAY_METHODS.put("pop", arrayPop);
    try ARRAY_METHODS.put("get", arrayGet);
    try ARRAY_METHODS.put("set", arraySet);
    try ARRAY_METHODS.put("clear", arrayClear);
    try ARRAY_METHODS.put("empty", arrayEmpty);
    try ARRAY_METHODS.put("len", arrayLen);

    ARRAY_TYPE = Value{
        .std_struct = .{
            .name = "Array",
            .constructor = arrayConstructor,
            .methods = ARRAY_METHODS,
        },
    };

    return ARRAY_TYPE;
}

fn arrayConstructor(
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
) !Value {
    const capacity: usize = if (args.len == 1) blk: {
        const val = try interpreter.evalExpr(args[0], env);
        if (val != .number) return error.TypeMismatch;
        break :blk @intFromFloat(val.number);
    } else 8;

    const array = try ArrayList.init(allocator, capacity);
    const wrapped = try allocator.create(ArrayListInstance);
    wrapped.* = .{ .array = array };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "Array",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = ARRAY_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn arrayPush(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getArrayInstance(this);
    try inst.array.push(val);
    return .nil;
}

fn arrayInsert(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    const value = try interpreter.evalExpr(args[1], env);
    if (index_val != .number) return error.TypeMismatch;

    const inst = try getArrayInstance(this);
    try inst.array.insert(@intFromFloat(index_val.number), value);
    return .nil;
}

fn arrayRemove(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) return error.TypeMismatch;

    const inst = try getArrayInstance(this);
    return try inst.array.remove(@intFromFloat(index_val.number));
}

fn arrayPop(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayInstance(this);
    return try inst.array.pop();
}

fn arrayGet(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) return error.TypeMismatch;

    const inst = try getArrayInstance(this);
    return try inst.array.get(@intFromFloat(index_val.number));
}

fn arraySet(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 2) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    const value = try interpreter.evalExpr(args[1], env);
    if (index_val != .number) return error.TypeMismatch;

    const inst = try getArrayInstance(this);
    try inst.array.set(@intFromFloat(index_val.number), value);
    return .nil;
}

fn arrayClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayInstance(this);
    inst.array.clear();
    return .nil;
}

fn arrayEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayInstance(this);
    return Value{ .boolean = inst.array.empty() };
}

fn arrayLen(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getArrayInstance(this);
    return Value{ .number = @floatFromInt(inst.array.len) };
}

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
        \\let length = a.len();
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
