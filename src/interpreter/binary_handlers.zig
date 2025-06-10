const std = @import("std");

const interpreter = @import("interpreter.zig");
const eval = @import("eval.zig");
const tokens = @import("../lexer/token.zig");

const Token = tokens.Token;
const Value = interpreter.Value;

pub fn plus(op: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = l + rhs.number,
            },
            .string => return .{
                .string = try std.fmt.allocPrint(op.allocator, "{d}{s}", .{ l, rhs.string }),
            },
            else => {
                try writer.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{s}", .{ l, rhs.string }),
            },
            .number => return .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{d}", .{ l, rhs.number }),
            },
            .boolean => return .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{s}", .{ l, if (rhs.boolean) "true" else "false" }),
            },
            .nil => return .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}nil", .{l}),
            },
            else => {
                try writer.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn minus(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = l - rhs.number,
            },
            else => {
                try writer.print("Cannot subtract type {s} from type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot subtract type {s} from type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn star(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .number = l * rhs.number },
            else => {
                try writer.print("Cannot multiply type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot multiply type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn slash(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .number = l / rhs.number },
            else => {
                try writer.print("Cannot divide type {s} by type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot divide type {s} by type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn mod(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .number = if (rhs.number < 0) 0 else @mod(l, rhs.number) },
            else => {
                try writer.print("Cannot mod type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot mod type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn bool_and(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .boolean => |l| switch (rhs) {
            .boolean => return .{ .boolean = l and rhs.boolean },
            else => {
                try writer.print("Cannot apply 'and' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot apply 'and' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn bool_or(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .boolean => |l| switch (rhs) {
            .boolean => return .{ .boolean = l or rhs.boolean },
            else => {
                try writer.print("Cannot apply 'or' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot apply 'or' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn equal(_: Token, lhs: Value, rhs: Value) !Value {
    return .{
        .boolean = lhs.eql(rhs),
    };
}

pub fn notEqual(_: Token, lhs: Value, rhs: Value) !Value {
    return .{
        .boolean = lhs.eql(rhs) == false,
    };
}

pub fn greater(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .boolean = l > rhs.number },
            else => {
                try writer.print("Cannot compare (>) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{ .boolean = std.mem.order(u8, l, rhs.string) == .gt },
            else => {
                try writer.print("Cannot compare (>) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot compare (>) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn greaterEqual(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .boolean = l >= rhs.number },
            else => {
                try writer.print("Cannot compare (>=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{
                .boolean = switch (std.mem.order(u8, l, rhs.string)) {
                    .gt, .eq => true,
                    else => false,
                },
            },
            else => {
                try writer.print("Cannot compare (>=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot compare (>=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn less(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .boolean = l < rhs.number },
            else => {
                try writer.print("Cannot compare (<) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{ .boolean = std.mem.order(u8, l, rhs.string) == .lt },
            else => {
                try writer.print("Cannot compare (<) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot compare (<) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn lessEqual(_: Token, lhs: Value, rhs: Value) !Value {
    const writer = eval.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .boolean = l <= rhs.number },
            else => {
                try writer.print("Cannot compare (<=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{
                .boolean = switch (std.mem.order(u8, l, rhs.string)) {
                    .lt, .eq => true,
                    else => false,
                },
            },
            else => {
                try writer.print("Cannot compare (<=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer.print("Cannot compare (<=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}
