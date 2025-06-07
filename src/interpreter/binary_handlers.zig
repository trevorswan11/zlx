const std = @import("std");

const interpreter = @import("interpreter.zig");
const tokens = @import("../lexer/token.zig");

const Token = tokens.Token;
const Value = interpreter.Value;

pub fn plus(op: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .number = l + rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{s}", .{ l, rhs.string }),
            },
            .number => .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{d}", .{ l, rhs.number }),
            },
            .nil => .{
                .string = try std.fmt.allocPrint(op.allocator, "{s}nil", .{l}),
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn minus(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .number = l - rhs.number,
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn star(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .number = l * rhs.number,
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn slash(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .number = l / rhs.number,
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
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
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .boolean = l > rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => .{
                .boolean = std.mem.order(u8, l, rhs.string) == .gt,
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn greaterEqual(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .boolean = l >= rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => .{
                .boolean = switch (std.mem.order(u8, l, rhs.string)) {
                    .gt, .eq => true,
                    else => false,
                },
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn less(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .boolean = l < rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => .{
                .boolean = std.mem.order(u8, l, rhs.string) == .lt,
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn lessEqual(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .boolean = l <= rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => .{
                .boolean = switch (std.mem.order(u8, l, rhs.string)) {
                    .lt, .eq => true,
                    else => false,
                },
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn mod(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => .{
                .number = if (rhs.number < 0) 0 else @mod(l, rhs.number),
            },
            else => error.TypeMismatch,
        },
        else => error.InvalidOperation,
    };
}

pub fn bool_and(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .boolean => |l| switch (rhs) {
            .boolean => .{
                .boolean = l and rhs.boolean,
            },
            else => error.TypeMismatch,
        },
        else => error.InvalidOperation,
    };
}

pub fn bool_or(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .boolean => |l| switch (rhs) {
            .boolean => .{
                .boolean = l or rhs.boolean,
            },
            else => error.TypeMismatch,
        },
        else => error.InvalidOperation,
    };
}
