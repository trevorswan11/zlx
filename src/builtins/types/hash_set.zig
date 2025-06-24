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

const HashSet = @import("dsa").HashSet(Value, interpreter.ValueContext);

pub const HashSetInstance = struct {
    set: HashSet,
};

fn getSetInstance(this: *Value) !*HashSetInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var SET_METHODS: std.StringHashMap(StdMethod) = undefined;
var SET_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    SET_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try SET_METHODS.put("insert", setInsert);
    try SET_METHODS.put("remove", setRemove);
    try SET_METHODS.put("contains", setContains);
    try SET_METHODS.put("clear", setClear);
    try SET_METHODS.put("size", setSize);
    try SET_METHODS.put("empty", setEmpty);
    try SET_METHODS.put("items", setItems);
    try SET_METHODS.put("str", setStr);

    SET_TYPE = .{
        .std_struct = .{
            .name = "set",
            .constructor = setConstructor,
            .methods = SET_METHODS,
        },
    };

    return SET_TYPE;
}

fn setConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const set = try HashSet.init(env.allocator);
    const wrapped = try env.allocator.create(HashSetInstance);
    wrapped.* = .{ .set = set };

    if (args.len > 1) {
        try writer_err.print("set(optional_array) expects at most 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    if (args.len == 1) {
        const input = try interpreter.evalExpr(args[0], env);
        const raw_input = input.deref();

        if (raw_input != .array) {
            try writer_err.print("set(array) expects an array argument but got a(n) {s}\n", .{@tagName(raw_input)});
            return error.TypeMismatch;
        }

        for (raw_input.array.items) |item| {
            try wrapped.set.insert(item);
        }
    }

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "set",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = SET_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn setInsert(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("set.insert(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getSetInstance(this);
    try inst.set.insert(val);
    return .nil;
}

fn setRemove(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("set.remove(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getSetInstance(this);
    return .{
        .boolean = inst.set.remove(val),
    };
}

fn setContains(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("set.contains(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getSetInstance(this);
    return .{
        .boolean = inst.set.contains(val),
    };
}

fn setClear(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    inst.set.clear();
    return .nil;
}

fn setSize(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    return .{
        .number = @floatFromInt(inst.set.size()),
    };
}

fn setEmpty(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    return .{
        .boolean = inst.set.empty(),
    };
}

pub fn setItems(this: *Value, _: []const *ast.Expr, env: *Environment) !Value {
    const inst = try getSetInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    var itr = inst.set.map.iterator();
    while (itr.next()) |entry| {
        try vals.append(entry.key_ptr.*);
    }

    return .{
        .array = vals,
    };
}

fn setStr(this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    return .{
        .string = try toString(inst.set),
    };
}

pub fn toString(set: HashSet) ![]const u8 {
    var buffer = std.ArrayList(u8).init(set.allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    try writer.print("[", .{});
    var it = set.map.iterator();
    while (it.next()) |entry| {
        try writer.print(" {s}", .{try entry.key_ptr.*.toString(set.allocator)});
    }
    try writer.print(" ]", .{});

    return try buffer.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "hash_set_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import set;
        \\let s = new set();
        \\s.insert("a");
        \\s.insert("b");
        \\let c = s.contains("a");
        \\let d = s.contains("z");
        \\let x = s.remove("a");
        \\let y = s.contains("a");
        \\let n = s.size();
        \\let e = s.empty();
        \\
        \\let s2 = new set(["x", "y", "x"]);
        \\let v1 = s2.contains("x");
        \\let v2 = s2.contains("y");
        \\let v3 = s2.contains("z");
        \\let sz = s2.size();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const c = try env.get("c");
    const d = try env.get("d");
    const x = try env.get("x");
    const y = try env.get("y");
    const n = try env.get("n");
    const e = try env.get("e");

    try testing.expect(c == .boolean);
    try testing.expect(d == .boolean);
    try testing.expect(x == .boolean);
    try testing.expect(y == .boolean);
    try testing.expect(n == .number);
    try testing.expect(e == .boolean);

    try testing.expect(c.boolean);
    try testing.expect(!d.boolean);
    try testing.expect(x.boolean);
    try testing.expect(!y.boolean);
    try testing.expectEqual(@as(f64, 1.0), n.number);
    try testing.expect(!e.boolean);

    try testing.expect((try env.get("v1")).boolean);
    try testing.expect((try env.get("v2")).boolean);
    try testing.expect(!(try env.get("v3")).boolean);
    try testing.expectEqual(@as(f64, 2.0), (try env.get("sz")).number);
}
