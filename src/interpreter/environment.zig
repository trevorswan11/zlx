const std = @import("std");

pub const eval = @import("eval.zig");
pub const evalExpr = eval.evalExpr;
pub const evalStmt = eval.evalStmt;

pub const Value = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    array: std.ArrayList(Value),
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

    pub fn toString(self: Value, allocator: std.mem.Allocator) []const u8 {
        return switch (self) {
            .number => |n| std.fmt.allocPrint(allocator, "{d}", .{n}) catch "NaN",
            .string => |s| s,
            .boolean => |b| if (b) "true" else "false",
            .array => |a| stringArray(a, allocator) catch "[]",
            .nil => "nil",
        };
    }
};

pub const EvalResult = union(enum) {
    value: Value,
    returned: Value,
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
        if (self.values.contains(name)) {
            try self.values.put(name, value);
        } else if (self.parent) |p| {
            try p.assign(name, value);
        } else {
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
