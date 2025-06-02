const std = @import("std");

const ast = @import("../ast/ast.zig");
pub const eval = @import("eval.zig");
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
    class: struct {
        name: []const u8,
        body: std.ArrayList(*ast.Stmt),
        constructor: ?*ast.Stmt,
    },
    reference: *Value,
    nil,

    fn stringArray(list: std.ArrayList(Value), allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        try str_builder.append('[');
        for (list.items, 0..) |item, i| {
            if (i != 0 and i != list.items.len) try str_builder.append(' ');
            const item_str = item.toString(allocator);
            defer allocator.free(item_str);
            try str_builder.appendSlice(item_str);
        }
        try str_builder.append(']');

        return try str_builder.toOwnedSlice();
    }

    fn stringFunction(parameters: []const []const u8, body: std.ArrayList(*ast.Stmt), allocator: std.mem.Allocator) ![]const u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        try str_builder.appendSlice("FN Parameters:\n");
        for (parameters) |param| {
            const formatted = try std.fmt.allocPrint(allocator, "  {s}\n", .{param});
            defer allocator.free(formatted);
            try str_builder.appendSlice(formatted);
        }
        const len_str = try std.fmt.allocPrint(allocator, "FN Body Len: {d}\n", .{body.items.len});
        // TODO: toString for stmts (not just strings)
        defer allocator.free(len_str);
        try str_builder.appendSlice(len_str);

        return try str_builder.toOwnedSlice();
    }

    fn stringObject(object: std.StringHashMap(Value), allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        try str_builder.appendSlice("[obj]:\n");
        var itr = object.iterator();
        while (itr.next()) |e| {
            try str_builder.appendSlice(e.key_ptr.*);
            try str_builder.appendSlice(": ");
            const value_str = e.value_ptr.toString(allocator);
            defer allocator.free(value_str);
            try str_builder.appendSlice(value_str);
            try str_builder.append('\n');
        }
        _ = str_builder.pop();

        return try str_builder.toOwnedSlice();
    }

    fn stringClass(name: []const u8, body: std.ArrayList(*ast.Stmt), ctor: ?*ast.Stmt, allocator: std.mem.Allocator) ![]u8 {
        var str_builder = std.ArrayList(u8).init(allocator);
        defer str_builder.deinit();

        const formatted_name = try std.fmt.allocPrint(allocator, "Class: {s}\n", .{name});
        defer allocator.free(formatted_name);
        try str_builder.appendSlice(formatted_name);

        const formatted_len = try std.fmt.allocPrint(allocator, "Class Body Len: {d}\n", .{body.items.len});
        defer allocator.free(formatted_len);
        try str_builder.appendSlice(formatted_len);
        // TODO: toString for stmts (not just strings)

        const formatted_ctor = try std.fmt.allocPrint(allocator, "Constructor: {s}\n", .{if (ctor) |_| "true" else "false"});
        defer allocator.free(formatted_ctor);
        try str_builder.appendSlice(formatted_ctor);

        return try str_builder.toOwnedSlice();
    }

    pub fn toString(self: Value, allocator: std.mem.Allocator) []const u8 {
        return switch (self) {
            .number => |n| std.fmt.allocPrint(allocator, "{d}", .{n}) catch "NaN",
            .string => |s| s,
            .boolean => |b| if (b) "true" else "false",
            .array => |a| stringArray(a, allocator) catch "[]",
            .function => |f| stringFunction(f.parameters, f.body, allocator) catch "INVALID_FN",
            .object => |o| stringObject(o, allocator) catch "INVALID_OBJ",
            .class => |c| stringClass(c.name, c.body, c.constructor, allocator) catch "INVALID_CLASS",
            .reference => |r| std.fmt.allocPrint(allocator, "References Val: {s}", .{r.toString(allocator)}) catch "INVALID_REF",
            .nil => "nil",
        };
    }

    pub fn deref(self: Value) Value {
        return if (self == .reference) self.reference.* else self;
    }
};

pub const Environment = struct {
    const Self = @This();

    values: std.StringHashMap(Value),
    allocator: std.mem.Allocator,
    parent: ?*Environment,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment) Self {
        return Environment{
            .values = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
            .parent = parent,
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
    }

    pub fn define(self: *Self, name: []const u8, value: Value) !void {
        try self.values.put(name, value);
    }

    pub fn assign(self: *Self, name: []const u8, value: Value) !void {
        const stderr = std.io.getStdErr().writer();
        if (self.values.contains(name)) {
            try self.values.put(name, value);
        } else if (self.parent) |p| {
            try p.assign(name, value);
        } else {
            try stderr.print("Undefined Value Error: {s}", .{value.toString(self.allocator)});
            return error.UndefinedVariable;
        }
    }

    pub fn get(self: *Self, name: []const u8) !Value {
        if (self.values.get(name)) |val| {
            return val;
        } else if (self.parent) |p| {
            return p.get(name);
        } else {
            return error.UndefinedValue;
        }
    }
};
