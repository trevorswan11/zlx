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

const HashMap = @import("dsa").HashMap(Value, Value, interpreter.ValueContext);

pub const HashMapInstance = struct {
    map: HashMap,
};

fn getMapInstance(this: *Value) !*HashMapInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var MAP_METHODS: std.StringHashMap(StdMethod) = undefined;
var MAP_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    MAP_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try MAP_METHODS.put("put", mapPut);
    try MAP_METHODS.put("get", mapGet);
    try MAP_METHODS.put("remove", mapRemove);
    try MAP_METHODS.put("contains", mapContains);
    try MAP_METHODS.put("clear", mapClear);
    try MAP_METHODS.put("size", mapSize);

    MAP_TYPE = .{
        .std_struct = .{
            .name = "map",
            .constructor = mapConstructor,
            .methods = MAP_METHODS,
        },
    };

    return MAP_TYPE;
}

fn mapConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const map = try HashMap.init(allocator);
    const wrapped = try allocator.create(HashMapInstance);
    wrapped.* = .{ .map = map };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "map",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = MAP_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn mapPut(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("map.put(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const key = try interpreter.evalExpr(args[0], env);
    const val = try interpreter.evalExpr(args[1], env);
    const inst = try getMapInstance(this);
    try inst.map.put(key, val);
    return .nil;
}

fn mapGet(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("map.get(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const key = try interpreter.evalExpr(args[0], env);
    const inst = try getMapInstance(this);
    return inst.map.find(key) orelse .nil;
}

fn mapRemove(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("map.remove(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const key = try interpreter.evalExpr(args[0], env);
    const inst = try getMapInstance(this);
    return inst.map.remove(key) orelse .nil;
}

fn mapContains(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("map.contains(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const key = try interpreter.evalExpr(args[0], env);
    const inst = try getMapInstance(this);
    return .{
        .boolean = inst.map.containsKey(key),
    };
}

fn mapClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getMapInstance(this);
    inst.map.clear();
    return .nil;
}

fn mapSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getMapInstance(this);
    return .{
        .number = @floatFromInt(inst.map.size()),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "hash_map_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import map;
        \\let m = new map();
        \\m.put("x", 1);
        \\m.put("y", 2);
        \\let a = m.get("x");
        \\let b = m.get("y");
        \\let c = m.get("z");
        \\let has = m.contains("y");
        \\let gone = m.remove("y");
        \\let empty = m.contains("y");
        \\let size = m.size();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const a = try env.get("a");
    const b = try env.get("b");
    const c = try env.get("c");
    const has = try env.get("has");
    const gone = try env.get("gone");
    const empty = try env.get("empty");
    const size = try env.get("size");

    try testing.expect(a == .number);
    try testing.expect(b == .number);
    try testing.expect(c == .nil);
    try testing.expect(gone == .number);
    try testing.expect(has.boolean);
    try testing.expect(!empty.boolean);
    try testing.expectEqual(@as(f64, 1.0), a.number);
    try testing.expectEqual(@as(f64, 2.0), b.number);
    try testing.expectEqual(@as(f64, 2.0), gone.number);
    try testing.expectEqual(@as(f64, 1.0), size.number);
}
