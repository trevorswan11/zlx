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

const HashMap = @import("dsa").HashMap(Value, Value, interpreter.ValueContext);
pub const HashMapInstance = struct {
    map: HashMap,
};

fn getMapInstance(this: *Value) !*HashMapInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
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
    try MAP_METHODS.put("empty", mapEmpty);
    try MAP_METHODS.put("items", mapItems);
    try MAP_METHODS.put("str", mapStr);

    MAP_TYPE = .{
        .std_struct = .{
            .name = "map",
            .constructor = mapConstructor,
            .methods = MAP_METHODS,
        },
    };

    return MAP_TYPE;
}

fn mapConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "map", "ctor", "");

    const map = try HashMap.init(env.allocator);
    const wrapped = try env.allocator.create(HashMapInstance);
    wrapped.* = .{
        .map = map,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "map",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = MAP_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn mapPut(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectValues(args, env, 2, "map", "put", "key, val");
    const key = parts[0];
    const val = parts[1];

    const inst = try getMapInstance(this);
    try inst.map.put(key, val);
    return .nil;
}

fn mapGet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const key = (try expectValues(args, env, 1, "map", "get", "key"))[0];
    const inst = try getMapInstance(this);
    return inst.map.find(key) orelse .nil;
}

fn mapRemove(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const key = (try expectValues(args, env, 1, "map", "remove", "key"))[0];
    const inst = try getMapInstance(this);
    return inst.map.remove(key) orelse .nil;
}

fn mapContains(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const key = (try expectValues(args, env, 1, "map", "contains", "key"))[0];
    const inst = try getMapInstance(this);
    return .{
        .boolean = inst.map.containsKey(key),
    };
}

fn mapClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "map", "clear", "");
    const inst = try getMapInstance(this);
    inst.map.clear();
    return .nil;
}

fn mapSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "map", "size", "");
    const inst = try getMapInstance(this);
    return .{
        .number = @floatFromInt(inst.map.size()),
    };
}

fn mapEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "map", "empty", "");
    const inst = try getMapInstance(this);
    return .{
        .boolean = inst.map.size() == 0,
    };
}

pub fn mapItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "map", "items", "");
    const inst = try getMapInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    var itr = inst.map.map.iterator();
    while (itr.next()) |entry| {
        try vals.append(.{
            .pair = .{
                .first = entry.key_ptr,
                .second = entry.value_ptr,
            },
        });
    }

    return .{
        .array = vals,
    };
}

fn mapStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "map", "str", "");
    const inst = try getMapInstance(this);
    return .{
        .string = try toString(inst.map),
    };
}

pub fn toString(map: HashMap) ![]const u8 {
    var buffer = std.ArrayList(u8).init(map.allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    var it = map.map.iterator();
    while (it.next()) |entry| {
        try writer.print("Key {s}, Value {s}", .{
            try entry.key_ptr.*.toString(map.allocator),
            try entry.value_ptr.*.toString(map.allocator),
        });
        try writer.print("\n", .{});
    }
    _ = buffer.pop();

    return try buffer.toOwnedSlice();
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
