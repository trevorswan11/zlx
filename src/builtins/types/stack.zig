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

const Stack = @import("dsa").Stack(Value);
pub const StackInstance = struct {
    stack: Stack,
};

fn getStackInstance(this: *Value) !*StackInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var STACK_METHODS: std.StringHashMap(StdMethod) = undefined;
var STACK_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    STACK_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try STACK_METHODS.put("push", stackPush);
    try STACK_METHODS.put("pop", stackPop);
    try STACK_METHODS.put("peek", stackPeek);
    try STACK_METHODS.put("size", stackSize);
    try STACK_METHODS.put("empty", stackEmpty);
    try STACK_METHODS.put("clear", stackClear);
    try STACK_METHODS.put("items", stackItems);
    try STACK_METHODS.put("str", stackStr);

    STACK_TYPE = .{
        .std_struct = .{
            .name = "stack",
            .constructor = stackConstructor,
            .methods = STACK_METHODS,
        },
    };

    return STACK_TYPE;
}

fn stackConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "ctor", "");

    const stack = try Stack.init(env.allocator);
    const wrapped = try env.allocator.create(StackInstance);
    wrapped.* = .{
        .stack = stack,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "stack",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = STACK_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn stackPush(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const value = (try expectValues(args, env, 1, "stack", "push", "value"))[0];
    const inst = try getStackInstance(this);
    try inst.stack.push(value);
    return .nil;
}

fn stackPop(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "pop", "");
    const inst = try getStackInstance(this);
    const result = inst.stack.pop();
    return result orelse .nil;
}

fn stackPeek(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "peek", "");
    const inst = try getStackInstance(this);
    const result = inst.stack.peek();
    return result orelse .nil;
}

fn stackSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "size", "");
    const inst = try getStackInstance(this);
    return .{
        .number = @floatFromInt(inst.stack.list.len),
    };
}

fn stackEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "empty", "");
    const inst = try getStackInstance(this);
    return .{
        .boolean = inst.stack.list.empty(),
    };
}

fn stackClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "clear", "");
    const inst = try getStackInstance(this);
    inst.stack.list.clear();
    return .nil;
}

pub fn stackItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "items", "");
    const inst = try getStackInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    var itr = inst.stack.list.begin();
    while (itr.next()) |val| {
        try vals.append(val.*);
    }

    return .{
        .array = vals,
    };
}

fn stackStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "stack", "str", "");
    const inst = try getStackInstance(this);
    const strFn = @import("list.zig").toString;
    return .{
        .string = try strFn(inst.stack.list),
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "stack_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import stack;
        \\let s = new stack();
        \\s.push(1);
        \\s.push(2);
        \\s.push(3);
        \\let a = s.peek();
        \\let b = s.pop();
        \\let c = s.pop();
        \\let d = s.pop();
        \\let e = s.pop();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const a = try env.get("a");
    const b = try env.get("b");
    const c = try env.get("c");
    const d = try env.get("d");
    const e = try env.get("e");

    try testing.expectEqual(@as(f64, 3), a.number);
    try testing.expectEqual(@as(f64, 3), b.number);
    try testing.expectEqual(@as(f64, 2), c.number);
    try testing.expectEqual(@as(f64, 1), d.number);
    try testing.expectEqual(Value.nil, e);
}
