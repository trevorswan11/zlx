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

const List = @import("dsa").List(Value);

pub const ListInstance = struct {
    list: List,
};

fn getListInstance(this: *Value) !*ListInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(internal.*.typed_val.value);
}

var LIST_METHODS: std.StringHashMap(StdMethod) = undefined;
var LIST_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    LIST_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try LIST_METHODS.put("append", listAppend);
    try LIST_METHODS.put("prepend", listPrepend);
    try LIST_METHODS.put("pop_head", listPopHead);
    try LIST_METHODS.put("pop_tail", listPopTail);
    try LIST_METHODS.put("get", listGet);
    try LIST_METHODS.put("remove", listRemove);
    try LIST_METHODS.put("discard", listDiscard);
    try LIST_METHODS.put("peek_head", listPeekHead);
    try LIST_METHODS.put("peek_tail", listPeekTail);
    try LIST_METHODS.put("clear", listClear);
    try LIST_METHODS.put("empty", listEmpty);
    try LIST_METHODS.put("size", listSize);
    try LIST_METHODS.put("str", listStr);

    LIST_TYPE = .{
        .std_struct = .{
            .name = "list",
            .constructor = listConstructor,
            .methods = LIST_METHODS,
        },
    };

    return LIST_TYPE;
}

fn listConstructor(
    allocator: std.mem.Allocator,
    _: []const *ast.Expr,
    _: *Environment,
) anyerror!Value {
    const list = try List.init(allocator);

    const wrapped = try allocator.create(ListInstance);
    wrapped.* = .{ .list = list };

    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "list",
        },
    };

    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try allocator.create(Value);
    type_ptr.* = LIST_TYPE;

    return .{
        .std_instance = .{
            .type = type_ptr,
            .fields = fields,
        },
    };
}

fn listAppend(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("list.append(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getListInstance(this);
    try inst.list.append(val);
    return .nil;
}

fn listPrepend(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("list.prepend(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const val = try interpreter.evalExpr(args[0], env);
    const inst = try getListInstance(this);
    try inst.list.prepend(val);
    return .nil;
}

fn listPopHead(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return inst.list.popHead() orelse .nil;
}

fn listPopTail(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return inst.list.popTail() orelse .nil;
}

fn listGet(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("list.get(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) {
        try writer_err.print("list.get(index) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getListInstance(this);
    return try inst.list.get(@intFromFloat(index_val.number));
}

fn listRemove(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("list.remove(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) {
        try writer_err.print("list.remove(index) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getListInstance(this);
    return try inst.list.remove(@intFromFloat(index_val.number));
}

fn listDiscard(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("list.discard(value) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) {
        try writer_err.print("list.discard(index) expects a number index but got a(n) {s}\n", .{@tagName(index_val)});
        return error.TypeMismatch;
    }

    const inst = try getListInstance(this);
    try inst.list.discard(@intFromFloat(index_val.number));
    return .nil;
}

fn listPeekHead(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return inst.list.peekHead() orelse .nil;
}

fn listPeekTail(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return inst.list.peekTail() orelse .nil;
}

fn listClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    inst.list.clear();
    return .nil;
}

fn listEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return .{
        .boolean = inst.list.empty(),
    };
}

fn listSize(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return .{
        .number = @floatFromInt(inst.list.len),
    };
}

fn listStr(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const inst = try getListInstance(this);
    return .{
        .string = try toString(inst.list),
    };
}

pub fn toString(list: List) ![]const u8 {
    var buffer = std.ArrayList(u8).init(list.allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    try writer.print("[ null", .{});
    var current = list.head;
    while (current) |node| {
        try writer.print(" <-> {s}", .{try node.value.toString(list.allocator)});
        current = node.next;
    }
    try writer.print(" <-> null ]", .{});

    return try buffer.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "list_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import list;
        \\let l = new list();
        \\l.append("a");
        \\l.append("b");
        \\l.append("c");
        \\let first = l.get(0);
        \\let last = l.pop_tail();
        \\let size = l.size();
        \\let is_empty = l.empty();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const first_val = try env.get("first");
    const last_val = try env.get("last");
    const size_val = try env.get("size");
    const is_empty_val = try env.get("is_empty");

    try testing.expect(first_val == .string);
    try testing.expect(last_val == .string);
    try testing.expect(size_val == .number);
    try testing.expect(is_empty_val == .boolean);

    try testing.expectEqualStrings("a", first_val.string);
    try testing.expectEqualStrings("c", last_val.string);
    try testing.expectEqual(@as(f64, 2.0), size_val.number);
    try testing.expect(!is_empty_val.boolean);
}
