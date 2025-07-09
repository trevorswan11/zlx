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

const List = @import("dsa").List(Value);
pub const ListInstance = struct {
    list: List,
};

fn getListInstance(this: *Value) !*ListInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;

    return @ptrCast(@alignCast(internal.*.typed_val.value));
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
    try LIST_METHODS.put("items", listItems);
    try LIST_METHODS.put("str", listStr);

    LIST_TYPE = .{
        .std_struct = .{
            .name = "linked_list",
            .constructor = listConstructor,
            .methods = LIST_METHODS,
        },
    };

    return LIST_TYPE;
}

fn listConstructor(args: []const *ast.Expr, env: *Environment) anyerror!Value {
    _ = try expectValues(args, env, 0, "list", "ctor", "");

    const list = try List.init(env.allocator);
    const wrapped = try env.allocator.create(ListInstance);
    wrapped.* = .{
        .list = list,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "linked_list",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = LIST_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn listAppend(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "list", "append", "value"))[0];
    const inst = try getListInstance(this);
    try inst.list.append(val);
    return .nil;
}

fn listPrepend(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const val = (try expectValues(args, env, 1, "list", "prepend", "value"))[0];
    const inst = try getListInstance(this);
    try inst.list.prepend(val);
    return .nil;
}

fn listPopHead(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "pop_head", "");
    const inst = try getListInstance(this);
    return inst.list.popHead() orelse .nil;
}

fn listPopTail(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "pop_tail", "");
    const inst = try getListInstance(this);
    return inst.list.popTail() orelse .nil;
}

fn listGet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index_val = (try expectNumberArgs(args, env, 1, "list", "get", "index"))[0];
    const inst = try getListInstance(this);
    return try inst.list.get(@intFromFloat(index_val));
}

fn listRemove(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index_val = (try expectNumberArgs(args, env, 1, "list", "remove", "index"))[0];
    const inst = try getListInstance(this);
    return try inst.list.remove(@intFromFloat(index_val));
}

fn listDiscard(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const index_val = (try expectNumberArgs(args, env, 1, "list", "discard", "index"))[0];
    const inst = try getListInstance(this);
    try inst.list.discard(@intFromFloat(index_val));
    return .nil;
}

fn listPeekHead(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "peek_head", "");
    const inst = try getListInstance(this);
    return inst.list.peekHead() orelse .nil;
}

fn listPeekTail(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "peek_tail", "");
    const inst = try getListInstance(this);
    return inst.list.peekTail() orelse .nil;
}

fn listClear(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "clear", "");
    const inst = try getListInstance(this);
    inst.list.clear();
    return .nil;
}

fn listEmpty(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "empty", "");
    const inst = try getListInstance(this);
    return .{
        .boolean = inst.list.empty(),
    };
}

fn listSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "size", "");
    const inst = try getListInstance(this);
    return .{
        .number = @floatFromInt(inst.list.len),
    };
}

pub fn listItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "items", "");
    const inst = try getListInstance(this);
    var vals = std.ArrayList(Value).init(env.allocator);

    var itr = inst.list.begin();
    while (itr.next()) |val| {
        try vals.append(val.*);
    }

    return .{
        .array = vals,
    };
}

fn listStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "list", "str", "");
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
        \\import linked_list;
        \\let l = new linked_list();
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
