const std = @import("std");

const interpreter = @import("interpreter.zig");
const eval = @import("eval.zig");
const token = @import("../lexer/token.zig");
const driver = @import("../utils/driver.zig");
const fns = @import("../builtins/fns.zig");

const Token = token.Token;
const Value = interpreter.Value;

const coerceBool = fns.coerceBool;

pub fn plus(op: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = l + rhs.number,
            },
            .string => return .{
                .string = try std.fmt.allocPrint(op.allocator, "{d}{s}", .{ l, rhs.string }),
            },
            else => {
                try writer_err.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
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
                try writer_err.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
                return error.TypeMismatch;
            },
        },
        .array => |a| switch (rhs) {
            .array => |b| {
                var summed = std.ArrayList(Value).init(op.allocator);
                for (a.items) |left_item| {
                    try summed.append(left_item);
                }
                for (b.items) |right_item| {
                    try summed.append(right_item);
                }

                return .{
                    .array = summed,
                };
            },
            else => {
                try writer_err.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot add type {s} to type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn minus(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = l - rhs.number,
            },
            else => {
                try writer_err.print("Cannot subtract type {s} from type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot subtract type {s} from type {s}\n", .{ @tagName(rhs), @tagName(lhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn star(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = l * rhs.number,
            },
            else => {
                try writer_err.print("Cannot multiply type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot multiply type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn slash(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = l / rhs.number,
            },
            else => {
                try writer_err.print("Cannot divide type {s} by type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot divide type {s} by type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn mod(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = if (rhs.number < 0) 0 else @mod(l, rhs.number),
            },
            else => {
                try writer_err.print("Cannot mod type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot mod type {s} with type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn boolAnd(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .boolean => |l| switch (rhs) {
            .boolean => return .{
                .boolean = l and rhs.boolean,
            },
            .number => return .{
                .boolean = l and coerceBool(
                    .{
                        .number = rhs.number,
                    },
                    null,
                ),
            },
            else => {
                try writer_err.print("Cannot apply 'and' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .number => |l| switch (rhs) {
            .boolean => return .{
                .boolean = coerceBool(
                    .{
                        .number = l,
                    },
                    null,
                ) and rhs.boolean,
            },
            else => {
                try writer_err.print("Cannot apply 'and' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
            .number => return .{
                .boolean = coerceBool(
                    .{
                        .number = l,
                    },
                    null,
                ) and coerceBool(
                    .{
                        .number = rhs.number,
                    },
                    null,
                ),
            },
        },
        else => {
            try writer_err.print("Cannot apply 'and' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn boolOr(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .boolean => |l| switch (rhs) {
            .boolean => return .{
                .boolean = l or rhs.boolean,
            },
            .number => return .{
                .boolean = l or coerceBool(
                    .{
                        .number = rhs.number,
                    },
                    null,
                ),
            },
            else => {
                try writer_err.print("Cannot apply 'or' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .number => |l| switch (rhs) {
            .boolean => return .{
                .boolean = coerceBool(
                    .{
                        .number = l,
                    },
                    null,
                ) or rhs.boolean,
            },
            else => {
                try writer_err.print("Cannot apply 'or' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
            .number => return .{
                .boolean = coerceBool(
                    .{
                        .number = l,
                    },
                    null,
                ) or coerceBool(
                    .{
                        .number = rhs.number,
                    },
                    null,
                ),
            },
        },
        else => {
            try writer_err.print("Cannot apply 'or' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
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
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .boolean = l > rhs.number,
            },
            else => {
                try writer_err.print("Cannot compare (>) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{
                .boolean = std.mem.order(u8, l, rhs.string) == .gt,
            },
            else => {
                try writer_err.print("Cannot compare (>) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot compare (>) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn greaterEqual(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .boolean = l >= rhs.number,
            },
            else => {
                try writer_err.print("Cannot compare (>=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
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
                try writer_err.print("Cannot compare (>=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot compare (>=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn less(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .boolean = l < rhs.number },
            else => {
                try writer_err.print("Cannot compare (<) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        .string => |l| switch (rhs) {
            .string => return .{ .boolean = std.mem.order(u8, l, rhs.string) == .lt },
            else => {
                try writer_err.print("Cannot compare (<) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot compare (<) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn lessEqual(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{ .boolean = l <= rhs.number },
            else => {
                try writer_err.print("Cannot compare (<=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
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
                try writer_err.print("Cannot compare (<=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot compare (<=) type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn bitwiseAnd(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = @floatFromInt(@as(i64, @intFromFloat(l)) & @as(i64, @intFromFloat(rhs.number))),
            },
            else => {
                try writer_err.print("Cannot apply '&' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot apply '&' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn bitwiseOr(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = @floatFromInt(@as(i64, @intFromFloat(l)) | @as(i64, @intFromFloat(rhs.number))),
            },
            else => {
                try writer_err.print("Cannot apply '|' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot apply '|' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}

pub fn bitwiseXor(_: Token, lhs: Value, rhs: Value) !Value {
    const writer_err = driver.getWriterErr();
    switch (lhs) {
        .number => |l| switch (rhs) {
            .number => return .{
                .number = @floatFromInt(@as(i64, @intFromFloat(l)) ^ @as(i64, @intFromFloat(rhs.number))),
            },
            else => {
                try writer_err.print("Cannot apply '^' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
                return error.TypeMismatch;
            },
        },
        else => {
            try writer_err.print("Cannot apply '^' to type {s} and type {s}\n", .{ @tagName(lhs), @tagName(rhs) });
            return error.TypeMismatch;
        },
    }
}
