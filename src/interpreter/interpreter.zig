const std = @import("std");

const ast = @import("../parser/ast.zig");
pub const eval = @import("eval.zig");
const token = @import("../lexer/token.zig");
const driver = @import("../utils/driver.zig");
const builtins = @import("../builtins/builtins.zig");

pub const evalExpr = eval.evalExpr;
pub const evalStmt = eval.evalStmt;

pub const Value = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    array: std.ArrayList(Value),
    function: struct {
        parameters: []const []const u8,
        body: std.ArrayList(*ast.Stmt),
        closure: *Environment,
    },
    object: std.StringHashMap(Value),
    structure: struct {
        name: []const u8,
        body: std.ArrayList(*ast.Stmt),
        constructor: ?*ast.Stmt,
        methods: std.StringHashMap(*ast.Stmt),
    },
    reference: *Value,
    bound_method: struct {
        instance: *Value,
        method: *ast.Stmt,
    },
    builtin: builtins.BuiltinModuleHandler,
    break_signal,
    continue_signal,
    return_value: *Value,
    typed_val: struct {
        value: *Value,
        _type: []const u8,
    },
    std_struct: struct {
        name: []const u8,
        constructor: builtins.StdCtor,
        methods: std.StringHashMap(builtins.StdMethod),
    },
    std_instance: struct {
        _type: *Value,
        fields: std.StringHashMap(*Value),
    },
    bound_std_method: struct {
        instance: *Value,
        method: builtins.StdMethod,
    },
    pair: struct {
        first: *Value,
        second: *Value,
    },
    nil,

    fn stringArray(list: std.ArrayList(Value), allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        try str_builder.append('[');
        for (list.items, 0..) |item, i| {
            if (i != 0 and i != list.items.len) {
                try str_builder.appendSlice(", ");
            }
            const item_str = try item.toString(allocator);
            defer allocator.free(item_str);
            try str_builder.appendSlice("\"");
            try str_builder.appendSlice(item_str);
            try str_builder.appendSlice("\"");
        }
        try str_builder.append(']');

        return try str_builder.toOwnedSlice();
    }

    fn stringFunction(parameters: []const []const u8, body: std.ArrayList(*ast.Stmt), allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        try str_builder.appendSlice("FN Parameters:\n");
        for (parameters) |param| {
            const formatted = try std.fmt.allocPrint(allocator, "  {s}\n", .{param});
            defer allocator.free(formatted);
            try str_builder.appendSlice(formatted);
        }
        const len_str = try std.fmt.allocPrint(allocator, "FN Body Len: {d}\n", .{body.items.len});
        defer allocator.free(len_str);
        try str_builder.appendSlice(len_str);

        try str_builder.appendSlice("FN Body:\n");
        for (body.items) |b| {
            const stmt_str = try b.toString(allocator);
            defer allocator.free(stmt_str);
            try str_builder.appendSlice(stmt_str);
            try str_builder.appendSlice("\n");
        }

        return try str_builder.toOwnedSlice();
    }

    fn stringObject(object: std.StringHashMap(Value), allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        try str_builder.appendSlice("[obj]: {\n");
        var itr = object.iterator();
        while (itr.next()) |e| {
            try str_builder.append(' ');
            try str_builder.appendSlice(e.key_ptr.*);
            try str_builder.appendSlice(": ");
            const value_str = try e.value_ptr.toString(allocator);
            defer allocator.free(value_str);
            try str_builder.appendSlice(value_str);
            try str_builder.appendSlice("\n");
        }
        try str_builder.append('}');

        return try str_builder.toOwnedSlice();
    }

    fn stringStruct(name: []const u8, body: std.ArrayList(*ast.Stmt), ctor: ?*ast.Stmt, allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        const formatted_name = try std.fmt.allocPrint(allocator, "Struct: {s}\n", .{name});
        defer allocator.free(formatted_name);
        try str_builder.appendSlice(formatted_name);

        const formatted_len = try std.fmt.allocPrint(allocator, "Struct Body Len: {d}\n", .{body.items.len});
        defer allocator.free(formatted_len);
        try str_builder.appendSlice(formatted_len);

        try str_builder.appendSlice("Struct Body:\n");
        for (body.items) |b| {
            const stmt_str = try b.toString(allocator);
            defer allocator.free(stmt_str);
            try str_builder.appendSlice(stmt_str);
            try str_builder.appendSlice("\n");
        }

        const formatted_ctor = try std.fmt.allocPrint(allocator, "Constructor: {s}\n", .{if (ctor) |_| "true" else "false"});
        defer allocator.free(formatted_ctor);
        try str_builder.appendSlice(formatted_ctor);

        return try str_builder.toOwnedSlice();
    }

    fn stringReference(ref: *Value, allocator: std.mem.Allocator) ![]u8 {
        const inner = try ref.toString(allocator);
        defer allocator.free(inner);
        return try std.fmt.allocPrint(allocator, "References Val: {s}", .{inner});
    }

    fn stringBoundMethod(bval: *Value, allocator: std.mem.Allocator) ![]u8 {
        const inner = try bval.toString(allocator);
        defer allocator.free(inner);
        return try std.fmt.allocPrint(allocator, "Bound to Instance: {s}", .{inner});
    }

    fn stringReturn(return_val: *Value, allocator: std.mem.Allocator) ![]u8 {
        const inner = try return_val.toString(allocator);
        defer allocator.free(inner);
        return try std.fmt.allocPrint(allocator, "Return: {s}", .{inner});
    }

    fn stringTyped(return_val: *Value, type_string: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const inner = try return_val.toString(allocator);
        defer allocator.free(inner);
        return try std.fmt.allocPrint(allocator, "Value: {s}, Type {s}", .{ inner, type_string });
    }

    fn stringPair(first: *Value, second: *Value, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "Pair: First = {s}; Second = {s}", .{
            try first.toString(allocator),
            try second.toString(allocator),
        });
    }

    pub fn toString(self: Value, allocator: std.mem.Allocator) anyerror![]u8 {
        return switch (self) {
            .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
            .string => |s| try std.fmt.allocPrint(allocator, "{s}", .{s}),
            .boolean => |b| try std.fmt.allocPrint(allocator, "{s}", .{if (b) "true" else "false"}),
            .array => |a| try stringArray(a, allocator),
            .function => |f| try stringFunction(f.parameters, f.body, allocator),
            .object => |o| try stringObject(o, allocator),
            .structure => |c| try stringStruct(c.name, c.body, c.constructor, allocator),
            .reference => |r| try stringReference(r, allocator),
            .bound_method => |bm| try stringBoundMethod(bm.instance, allocator),
            .builtin => |_| try std.fmt.allocPrint(allocator, "<Builtin Module>", .{}),
            .break_signal => |_| try std.fmt.allocPrint(allocator, "break", .{}),
            .continue_signal => |_| try std.fmt.allocPrint(allocator, "continue", .{}),
            .return_value => |r| try stringReturn(r, allocator),
            .typed_val => |t| try stringTyped(t.value, t._type, allocator),
            .std_struct => try std.fmt.allocPrint(allocator, "<Standard Library Struct>", .{}),
            .std_instance => try std.fmt.allocPrint(allocator, "<Standard Library Instance>", .{}),
            .bound_std_method => |bm| try stringBoundMethod(bm.instance, allocator),
            .pair => |p| try stringPair(p.first, p.second, allocator),
            .nil => try std.fmt.allocPrint(allocator, "nil", .{}),
        };
    }

    pub fn deref(self: Value) Value {
        return if (self == .reference) self.reference.* else self;
    }

    pub fn eql(self: Value, other: Value) bool {
        return switch (self) {
            .number => |n| other == .number and n == other.number,
            .string => |s| other == .string and std.mem.eql(u8, s, other.string),
            .boolean => |b| other == .boolean and b == other.boolean,
            .nil => other == .nil,
            .array => |arr_self| if (other == .array) blk: {
                const arr_other = other.array;
                if (arr_self.items.len != arr_other.items.len) {
                    break :blk false;
                }
                for (arr_self.items, arr_other.items) |a, b| {
                    if (!a.eql(b)) {
                        break :blk false;
                    }
                }
                break :blk true;
            } else false,
            .object => |obj_self| if (other == .object) blk: {
                const obj_other = other.object;
                if (obj_self.count() != obj_other.count()) {
                    break :blk false;
                }

                var iter = obj_self.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;

                    if (obj_other.get(key)) |other_val| {
                        if (!val.eql(other_val)) {
                            break :blk false;
                        }
                    } else break :blk false;
                }
                break :blk true;
            } else false,
            .reference => |ref_self| other == .reference and ref_self.eql(other.reference.*),
            else => false,
        };
    }

    pub fn compare(self: Value, other: Value) std.math.Order {
        const std_order = std.math.Order;

        const a = self.raw();
        const b = other.raw();

        return switch (a) {
            .number => |x| switch (b) {
                .number => std.math.order(x, b.number),
                else => std_order.gt,
            },
            .string => |x| switch (b) {
                .string => std.mem.order(u8, x, b.string),
                else => std_order.gt,
            },
            .boolean => |x| switch (b) {
                .boolean => std.math.order(@intFromBool(x), @intFromBool(b.boolean)),
                else => std_order.gt,
            },
            .nil => switch (b) {
                .nil => std_order.eq,
                else => std_order.lt,
            },
            else => blk: {
                // fallback to address comparison for non-comparable types
                const a_ptr = @intFromPtr(&a);
                const b_ptr = @intFromPtr(&b);
                break :blk std.math.order(a_ptr, b_ptr);
            },
        };
    }

    pub fn less(a: Value, b: Value) bool {
        return switch (a.compare(b)) {
            .lt => true,
            else => false,
        };
    }

    pub fn raw(self: *const Value) Value {
        var current = self.*;
        while (true) {
            current = switch (current) {
                .typed_val => current.typed_val.value.*,
                .reference => current.reference.*,
                else => return current,
            };
        }
    }

    pub fn boxValueString(str: []const u8, allocator: std.mem.Allocator) !*Value {
        const box = try allocator.create(Value);
        box.* = .{
            .string = str,
        };
        return box;
    }
};

pub const ValueContext = struct {
    pub fn hash(self: @This(), key: Value) u64 {
        var hasher = std.hash.Wyhash.init(0);
        switch (key) {
            .number => |n| hasher.update(&std.mem.toBytes(n)),
            .string => |s| hasher.update(s),
            .boolean => |b| hasher.update(&std.mem.toBytes(b)),
            .nil => hasher.update("nil"),
            .reference => |r| hasher.update(&std.mem.toBytes(@intFromPtr(r))),
            .typed_val => |tv| hasher.update(&std.mem.toBytes(@intFromPtr(tv.value))),
            .bound_method => |bm| {
                hasher.update(&std.mem.toBytes(@intFromPtr(bm.instance)));
                hasher.update(&std.mem.toBytes(@intFromPtr(bm.method)));
            },
            .return_value => |rv| hasher.update(&std.mem.toBytes(@intFromPtr(rv))),
            .break_signal => hasher.update("break"),
            .continue_signal => hasher.update("continue"),
            .array => |arr| {
                for (arr.items) |v| {
                    hasher.update(&std.mem.toBytes(hash(self, v)));
                }
            },
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |e| {
                    hasher.update(e.key_ptr.*);
                    hasher.update(&std.mem.toBytes(hash(self, e.value_ptr.*)));
                }
            },
            else => {
                // fallback: hash the tag only
                hasher.update(&std.mem.toBytes(@intFromEnum(key)));
            },
        }
        return hasher.final();
    }

    pub fn eql(_: @This(), a: Value, b: Value) bool {
        return a.eql(b);
    }
};

pub const Environment = struct {
    const Self = @This();

    values: std.StringHashMap(Value),
    constants: std.StringHashMap(void),
    allocator: std.mem.Allocator,
    parent: ?*Environment,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment) Self {
        return Environment{
            .values = std.StringHashMap(Value).init(allocator),
            .constants = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
            .parent = parent,
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
        self.constants.deinit();
    }

    pub fn define(self: *Self, name: []const u8, value: Value) !void {
        const writer_err = driver.getWriterErr();
        if (std.mem.eql(u8, name, "_")) {
            return;
        }

        if (self.values.contains(name)) {
            try writer_err.print("Duplicate Identifier: \"{s}\"\n", .{name});
            return error.DuplicateIdentifier;
        } else {
            try self.values.put(name, value);
        }
    }

    pub fn declareConstant(self: *Self, name: []const u8, value: Value) !void {
        const writer_err = driver.getWriterErr();
        if (std.mem.eql(u8, name, "_")) {
            return;
        }

        if (self.values.contains(name)) {
            try writer_err.print("Duplicate Identifier: \"{s}\"\n", .{name});
            return error.DuplicateIdentifier;
        } else {
            try self.values.put(name, value);
            try self.assign(name, value);
            try self.constants.put(name, {});
        }
    }

    pub fn assign(self: *Self, name: []const u8, value: Value) !void {
        const writer_err = driver.getWriterErr();
        if (std.mem.eql(u8, name, "_")) {
            return;
        }

        if (self.constants.contains(name)) {
            try writer_err.print("Identifier \"{s}\" is Constant\n", .{name});
            return error.ReassignmentToConstantVariable;
        }

        if (self.values.contains(name)) {
            try self.values.put(name, value);
        } else if (self.parent) |p| {
            try p.assign(name, value);
        } else {
            try writer_err.print("Identifier \"{s}\" is Undefined\n", .{name});
            return error.UndefinedValue;
        }
    }

    pub fn makeConstant(self: *Self, name: []const u8) !void {
        const writer_err = driver.getWriterErr();
        if (std.mem.eql(u8, name, "_")) {
            return;
        }

        if (!self.values.contains(name)) {
            try writer_err.print("Identifier \"{s}\" is Undefined\n", .{name});
            return error.UndefinedValue;
        }

        if (!self.constants.contains(name)) {
            try self.constants.put(name, {});
        }
    }

    pub fn stripConstant(self: *Self, name: []const u8) !void {
        const writer_err = driver.getWriterErr();
        if (std.mem.eql(u8, name, "_")) {
            return;
        }

        if (!self.values.contains(name)) {
            try writer_err.print("Identifier \"{s}\" is Undefined\n", .{name});
            return error.UndefinedValue;
        }

        if (self.constants.contains(name)) {
            _ = self.constants.remove(name, {});
        }
    }

    pub fn get(self: *Self, name: []const u8) !Value {
        const writer_err = driver.getWriterErr();

        if (self.values.get(name)) |val| {
            return val;
        } else if (self.parent) |p| {
            return p.get(name);
        } else {
            try writer_err.print("Identifier \"{s}\" is Undefined\n", .{name});
            return error.UndefinedValue;
        }
    }

    pub fn remove(self: *Self, name: []const u8) Value {
        _ = self.values.remove(name);
        _ = self.constants.remove(name);
        return .nil;
    }

    pub fn clear(self: *Self) void {
        self.values.clearRetainingCapacity();
    }

    pub fn boxExpr(self: *Self, e: ast.Expr) !*ast.Expr {
        const ptr = try self.allocator.create(ast.Expr);
        ptr.* = e;
        return ptr;
    }

    pub fn boxStmt(self: *Self, stmt: ast.Stmt) !*ast.Stmt {
        const ptr = try self.allocator.create(ast.Stmt);
        ptr.* = stmt;
        return ptr;
    }

    pub fn boxType(self: *Self, e: ast.Type) !*ast.Type {
        const ptr = try self.allocator.create(ast.Type);
        ptr.* = e;
        return ptr;
    }
};
