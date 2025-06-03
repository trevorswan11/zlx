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
        methods: std.StringHashMap(*ast.Stmt),
    },
    reference: *Value,
    bound_method: struct {
        instance: *Value,
        method: *ast.Stmt,
    },
    builtin: *const fn (
        allocator: std.mem.Allocator,
        args: []const *ast.Expr,
        env: *Environment,
    ) anyerror!Value,
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
            try str_builder.appendSlice(item_str);
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
        // TODO: toString for stmts (not just strings)
        defer allocator.free(len_str);
        try str_builder.appendSlice(len_str);

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

    pub fn toString(self: Value, allocator: std.mem.Allocator) anyerror![]u8 {
        return switch (self) {
            .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
            .string => |s| try std.fmt.allocPrint(allocator, "{s}", .{s}),
            .boolean => |b| try std.fmt.allocPrint(allocator, "{s}", .{if (b) "true" else "false"}),
            .array => |a| try stringArray(a, allocator),
            .function => |f| try stringFunction(f.parameters, f.body, allocator),
            .object => |o| try stringObject(o, allocator),
            .class => |c| try stringClass(c.name, c.body, c.constructor, allocator),
            .reference => |r| try stringReference(r, allocator),
            .bound_method => |bm| try stringBoundMethod(bm.instance, allocator),
            .builtin => |_| try std.fmt.allocPrint(allocator, "<Builtin Module>", .{}),
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
                if (arr_self.items.len != arr_other.items.len) break :blk false;
                for (arr_self.items, arr_other.items) |a, b| {
                    if (!a.eql(b)) break :blk false;
                }
                break :blk true;
            } else false,
            .object => |obj_self| if (other == .object) blk: {
                const obj_other = other.object;
                if (obj_self.count() != obj_other.count()) break :blk false;

                var iter = obj_self.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;

                    if (obj_other.get(key)) |other_val| {
                        if (!val.eql(other_val)) break :blk false;
                    } else break :blk false;
                }
                break :blk true;
            } else false,
            .reference => |ref_self| other == .reference and ref_self.eql(other.reference.*),
            .bound_method => |_| false,
            .function => |_| false,
            .class => |_| false,
            .builtin => |_| false,
        };
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
            const str = try value.toString(self.allocator);
            defer self.allocator.free(str);
            try stderr.print("Undefined Value Error: {s}", .{str});
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
