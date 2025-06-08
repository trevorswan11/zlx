const std = @import("std");

pub const parser = @import("../parser/parser.zig");
pub const ast = @import("../parser/ast.zig");
pub const interpreter = @import("../interpreter/interpreter.zig");

pub const eval = interpreter.eval;
pub const Environment = interpreter.Environment;
pub const Value = interpreter.Value;

pub const testing = std.testing;

pub const expect = testing.expect;
pub const expectEqual = testing.expectEqual;
pub const expectApproxEqAbs = testing.expectApproxEqAbs;
pub const expectEqualStrings = std.testing.expectEqualStrings;
pub const expectError = std.testing.expectError;

/// Returns the test allocator. This should only be used in temporary test programs
pub fn allocator() std.mem.Allocator {
    return testing.allocator;
}

/// Calls the parser's parse method on the source, removing parser include in
pub fn parse(alloc: std.mem.Allocator, source: []const u8) !*ast.Stmt {
    return try parser.parse(alloc, source);
}
