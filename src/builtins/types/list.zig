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
    try LIST_METHODS.put("popHead", listPopHead);
    try LIST_METHODS.put("popTail", listPopTail);
    try LIST_METHODS.put("get", listGet);
    try LIST_METHODS.put("remove", listRemove);
    try LIST_METHODS.put("discard", listDiscard);
    try LIST_METHODS.put("peekHead", listPeekHead);
    try LIST_METHODS.put("peekTail", listPeekTail);
    try LIST_METHODS.put("clear", listClear);
    try LIST_METHODS.put("empty", listEmpty);
    try LIST_METHODS.put("len", listLen);

    LIST_TYPE = Value{
        .std_struct = .{
            .name = "List",
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

    // Wrap it in a heap-allocated struct
    const wrapped = try allocator.create(ListInstance);
    wrapped.* = .{ .list = list };

    // Allocate a Value to hold the pointer to `wrapped`
    const internal_ptr = try allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(wrapped),
            .type = "List",
        },
    };

    // Prepare instance fields
    var fields = std.StringHashMap(*Value).init(allocator);
    try fields.put("__internal", internal_ptr);

    // Allocate the type pointer
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
    if (args.len != 1) return error.ArgumentCountMismatch;
    const val = try interpreter.evalExpr(args[0], env);
    const list = try getListInstance(this);
    try list.list.append(val);
    return .nil;
}

fn listPrepend(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const val = try interpreter.evalExpr(args[0], env);
    const list = try getListInstance(this);
    try list.list.prepend(val);
    return .nil;
}

fn listPopHead(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = args;
    _ = env;
    const list = try getListInstance(this);
    return list.list.popHead() orelse .nil;
}

fn listPopTail(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = args;
    _ = env;
    const list = try getListInstance(this);
    return list.list.popTail() orelse .nil;
}

fn listGet(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) return error.TypeMismatch;

    const list = try getListInstance(this);
    return try list.list.get(@intFromFloat(index_val.number));
}

fn listRemove(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) return error.TypeMismatch;

    const list = try getListInstance(this);
    return try list.list.remove(@intFromFloat(index_val.number));
}

fn listDiscard(_: std.mem.Allocator, this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    if (args.len != 1) return error.ArgumentCountMismatch;
    const index_val = try interpreter.evalExpr(args[0], env);
    if (index_val != .number) return error.TypeMismatch;

    const list = try getListInstance(this);
    try list.list.discard(@intFromFloat(index_val.number));
    return .nil;
}

fn listPeekHead(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const list = try getListInstance(this);
    return list.list.peekHead() orelse .nil;
}

fn listPeekTail(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const list = try getListInstance(this);
    return list.list.peekTail() orelse .nil;
}

fn listClear(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const list = try getListInstance(this);
    list.list.clear();
    return .nil;
}

fn listEmpty(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const list = try getListInstance(this);
    return Value{ .boolean = list.list.empty() };
}

fn listLen(_: std.mem.Allocator, this: *Value, _: []const *ast.Expr, _: *Environment) !Value {
    const list = try getListInstance(this);
    return Value{ .number = @floatFromInt(list.list.len) };
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
        \\let last = l.popTail();
        \\let size = l.len();
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
