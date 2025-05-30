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

    table: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Environment{
            .table = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.table.deinit();
    }

    pub fn define(self: *Self, name: []const u8, value: Value) !void {
        try self.table.put(name, value);
    }

    pub fn assign(self: *Self, name: []const u8, value: Value) !void {
        if (self.table.contains(name)) {
            try self.table.put(name, value);
        } else {
            return error.UndefinedVariable;
        }
    }

    pub fn get(self: *Self, name: []const u8) !Value {
        return self.table.get(name) orelse error.UndefinedValue;
    }
};
