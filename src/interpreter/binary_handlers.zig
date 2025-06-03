const std = @import("std");

const environment = @import("environment.zig");
const tokens = @import("../lexer/token.zig");

const Token = tokens.Token;
const Value = environment.Value;

pub fn plus(op: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => Value{
                .number = l + rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => Value{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{s}", .{ l, rhs.string }),
            },
            .number => Value{
                .string = try std.fmt.allocPrint(op.allocator, "{s}{d}", .{ l, rhs.number }),
            },
            .nil => Value{
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
            .number => Value{
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
            .number => Value{
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
            .number => Value{
                .number = l / rhs.number,
            },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

pub fn equal(_: Token, lhs: Value, rhs: Value) !Value {
    return Value{
        .boolean = lhs.eql(rhs),
    };
}

pub fn notEqual(_: Token, lhs: Value, rhs: Value) !Value {
    return Value{
        .boolean = lhs.eql(rhs) == false,
    };
}

pub fn greater(_: Token, lhs: Value, rhs: Value) !Value {
    return switch (lhs) {
        .number => |l| switch (rhs) {
            .number => Value{
                .boolean = l > rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => Value{
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
            .number => Value{
                .boolean = l >= rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => Value{
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
            .number => Value{
                .boolean = l < rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => Value{
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
            .number => Value{
                .boolean = l <= rhs.number,
            },
            else => error.TypeMismatch,
        },
        .string => |l| switch (rhs) {
            .string => Value{
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
            .number => Value{
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
            .boolean => Value{
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
            .boolean => Value{
                .boolean = l or rhs.boolean,
            },
            else => error.TypeMismatch,
        },
        else => error.InvalidOperation,
    };
}
