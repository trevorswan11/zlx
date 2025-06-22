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

fn stackConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) !Value {
    const stack = try Stack.init(allocator);
    const wrapped = try allocator.create(StackInstance);
    wrapped.* = .{
        .stack = stack,
    };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            .type = "stack",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = STACK_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn stackPush(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("stack.push(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const value = try eval.evalExpr(args[0], env);
    const inst = try getStackInstance(this);
    try inst.stack.push(value);
    return .nil;
}

fn stackPop(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getStackInstance(this);
    const result = inst.stack.pop();
    return result orelse .nil;
}

fn stackPeek(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getStackInstance(this);
    const result = inst.stack.peek();
    return result orelse .nil;
}

fn stackSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getStackInstance(this);
    return .{
        .number = @floatFromInt(inst.stack.list.len),
    };
}

fn stackEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getStackInstance(this);
    return .{
        .boolean = inst.stack.list.empty(),
    };
}

fn stackClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getStackInstance(this);
    inst.stack.list.clear();
    return .nil;
}

pub fn stackItems(allocator: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getStackInstance(this);
    var vals = std.ArrayList(Value).init(allocator);

    var itr = inst.stack.list.begin();
    while (itr.next()) |val| {
        try vals.append(val.*);
    }

    return .{
        .array = vals,
    };
}

fn stackStr(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
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
