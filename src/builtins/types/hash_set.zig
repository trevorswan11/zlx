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

const HashSet = @import("dsa").HashSet(Value, interpreter.ValueContext);

pub const HashSetInstance = struct {
    set: HashSet,
};

fn getSetInstance(this: *Value) !*HashSetInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
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

    SET_TYPE = .{
        .std_struct = .{
            .name = "Set",
            .constructor = setConstructor,
            .methods = SET_METHODS,
        },
    };

    return SET_TYPE;
}

fn setConstructor(
    allocator: std.mem.Allocator,
    args: []const *ast.Expr,
    env: *Environment,
) !Value {
    const writer_err = driver.getWriterErr();
    const set = try HashSet.init(allocator);
    const wrapped = try allocator.create(HashSetInstance);
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

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "Set",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = SET_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn setInsert(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
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

fn setRemove(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
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

fn setContains(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
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

fn setClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    inst.set.clear();
    return .nil;
}

fn setSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    return .{
        .number = @floatFromInt(inst.set.size()),
    };
}

fn setEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getSetInstance(this);
    return .{
        .boolean = inst.set.empty(),
    };
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
