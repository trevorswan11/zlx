const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const eval = interpreter.eval;

const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;

pub fn load(allocator: std.mem.Allocator) !Value {
    const map = std.StringHashMap(Value).init(allocator);

    return .{
        .object = map,
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "csv_builtin" {}
