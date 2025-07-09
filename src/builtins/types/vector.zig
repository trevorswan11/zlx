const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

const StdMethod = builtins.StdMethod;
const StdCtor = builtins.StdCtor;

const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

const expectArrayRef = builtins.expectArrayRef;
const expectNumberArrays = builtins.expectNumberArrays;

fn expectVector(val: *Value, module_name: []const u8, func_name: []const u8) !*VectorInstance {
    const writer_err = driver.getWriterErr();
    const name = try builtins.getStdStructName(val);
    if (std.mem.eql(u8, name, "vector")) {
        return try getVectorInstance(val);
    } else {
        try writer_err.print("{s} module: {s} expected a vector argument but got a(n) {s}\n", .{ module_name, func_name, name });
        return error.ExpectedVectorArg;
    }
}

pub const VectorInstance = struct {
    vector: std.ArrayList(f64),
};

pub fn getVectorInstance(this: *Value) !*VectorInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

pub var VECTOR_METHODS: std.StringHashMap(StdMethod) = undefined;
pub var VECTOR_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    VECTOR_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try VECTOR_METHODS.put("add", vectorAdd);
    try VECTOR_METHODS.put("sub", vectorSub);
    try VECTOR_METHODS.put("dot", vectorDot);
    try VECTOR_METHODS.put("scale", vectorScale);
    try VECTOR_METHODS.put("norm", vectorNorm);
    try VECTOR_METHODS.put("normalize", vectorNormalize);
    try VECTOR_METHODS.put("dim", vectorSize);
    try VECTOR_METHODS.put("project", vectorProject);
    try VECTOR_METHODS.put("angle", vectorAngle);
    try VECTOR_METHODS.put("cross", vectorCross);
    try VECTOR_METHODS.put("equals", vectorEquals);
    try VECTOR_METHODS.put("set", vectorSet);
    try VECTOR_METHODS.put("get", vectorGet);
    try VECTOR_METHODS.put("items", vectorItems);
    try VECTOR_METHODS.put("size", vectorSize);
    try VECTOR_METHODS.put("str", vectorStr);

    VECTOR_TYPE = .{
        .std_struct = .{
            .name = "vector",
            .constructor = vectorConstructor,
            .methods = VECTOR_METHODS,
        },
    };

    return VECTOR_TYPE;
}

fn vectorConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 0) {
        try writer_err.print("vector(args..) expects at least 1 arguments but got 0\n", .{});
        return error.ArgumentCountMismatch;
    }

    const vec: []const f64 = blk: switch (args.len) {
        // Vector can be created out of an array
        1 => {
            const arg_arrays = try expectArrayArgs(args, env, 1, "vector", "ctor");
            const vals = (try expectNumberArrays(env.allocator, arg_arrays, "vector", "ctor"))[0];
            if (vals.len == 0 or vals.len > 4) {
                try writer_err.print("vector(array) expects an array of size 4 or less, found an array length {d}\n", .{vals.len});
                return error.ArraySizeMismatch;
            }
            break :blk vals;
        },

        2 => break :blk try expectNumberArgs(args, env, 2, "vector", "ctor"),
        3 => break :blk try expectNumberArgs(args, env, 3, "vector", "ctor"),
        4 => break :blk try expectNumberArgs(args, env, 4, "vector", "ctor"),
        else => {
            try writer_err.print("vector(args..) expects a maximum of 4 arguments but got {d}\n", .{args.len});
            return error.ArgumentCountMismatch;
        },
    };

    var arr = try std.ArrayList(f64).initCapacity(env.allocator, vec.len);
    try arr.appendSlice(vec);
    const wrapped = try env.allocator.create(VectorInstance);
    wrapped.* = .{
        .vector = arr,
    };

    const internal_ptr = try env.allocator.create(Value);
    internal_ptr.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "vector",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_ptr);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = VECTOR_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

pub fn vectorAdd(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    var other_val = (try expectValues(args, env, 1, "vector", "add"))[0];
    const other = try expectVector(&other_val, "vector", "add");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = other.vector;

    if (a.items.len != b.items.len) {
        try writer_err.print("Cannot add vector of length {d} to vector of length {d}\n", .{ a.items.len, b.items.len });
        return error.VectorSizeMismatch;
    }

    for (a.items, 0..) |*item, i| {
        item.* += b.items[i];
    }
    return this.*;
}

pub fn vectorSub(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    var other_val = (try expectValues(args, env, 1, "vector", "sub"))[0];
    const other = try expectVector(&other_val, "vector", "sub");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = other.vector;

    if (a.items.len != b.items.len) {
        try writer_err.print("Cannot sub vector of length {d} to vector of length {d}\n", .{ a.items.len, b.items.len });
        return error.VectorSizeMismatch;
    }

    for (a.items, 0..) |*item, i| {
        item.* -= b.items[i];
    }
    return this.*;
}

pub fn vectorDot(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    var other_val = (try expectValues(args, env, 1, "vector", "dot"))[0];
    const other = try expectVector(&other_val, "vector", "dot");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = other.vector;

    if (a.items.len != b.items.len) {
        try writer_err.print("Cannot dot vector of length {d} to vector of length {d}\n", .{ a.items.len, b.items.len });
        return error.VectorSizeMismatch;
    }

    var result: f64 = 0;
    for (a.items, b.items) |item_one, item_two| {
        result += item_one * item_two;
    }
    return .{
        .number = result,
    };
}

pub fn vectorScale(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const inst = try getVectorInstance(this);
    const scalar = (try expectNumberArgs(args, env, 1, "vector", "scale"))[0];
    for (inst.vector.items) |*item| {
        item.* *= scalar;
    }
    return this.*;
}

pub fn vectorNorm(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "vector", "norm");

    const inst = try getVectorInstance(this);
    const vec = inst.vector;

    var sum_sq: f64 = 0;
    for (vec.items) |v| {
        sum_sq += v * v;
    }

    return .{
        .number = std.math.sqrt(sum_sq),
    };
}

pub fn vectorNormalize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    _ = try expectValues(args, env, 0, "vector", "normalize");

    const inst = try getVectorInstance(this);
    const vec = inst.vector;

    var sum_sq: f64 = 0;
    for (vec.items) |v| {
        sum_sq += v * v;
    }

    const norm = std.math.sqrt(sum_sq);
    if (norm == 0) {
        try writer_err.print("vector.normalize() failed: zero vector has no direction\n", .{});
        return error.DivisionByZero;
    }

    for (vec.items) |*v| {
        v.* /= norm;
    }

    return this.*;
}

pub fn vectorProject(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    var other_val = (try expectValues(args, env, 1, "vector", "project"))[0];
    const onto = try expectVector(&other_val, "vector", "project");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = onto.vector;

    if (a.items.len != b.items.len) {
        try writer_err.print("vector.project(onto_vec): cannot project vector of length {d} onto vector of length {d}\n", .{ a.items.len, b.items.len });
        return error.VectorSizeMismatch;
    }

    var dot_ab: f64 = 0;
    var dot_bb: f64 = 0;
    for (a.items, b.items) |x, y| {
        dot_ab += x * y;
        dot_bb += y * y;
    }

    if (dot_bb == 0) {
        try writer_err.print("vector.project(onto_vec): cannot project onto a zero vector\n", .{});
        return error.DivisionByZero;
    }

    const scalar = dot_ab / dot_bb;
    for (a.items, 0..) |_, i| {
        a.items[i] = scalar * b.items[i];
    }

    return this.*;
}

pub fn vectorAngle(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    var other_val = (try expectValues(args, env, 1, "vector", "angle"))[0];
    const other = try expectVector(&other_val, "vector", "angle");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = other.vector;

    if (a.items.len != b.items.len) {
        try writer_err.print("vector.angle(other_vec): cannot compute angle with vector of length {d} and {d}\n", .{ a.items.len, b.items.len });
        return error.VectorSizeMismatch;
    }

    var dot: f64 = 0;
    var norm_a: f64 = 0;
    var norm_b: f64 = 0;

    for (a.items, b.items) |x, y| {
        dot += x * y;
        norm_a += x * x;
        norm_b += y * y;
    }

    const denom = std.math.sqrt(norm_a) * std.math.sqrt(norm_b);
    if (denom == 0) {
        try writer_err.print("vector.angle(other_vec): cannot compute angle with zero vector\n", .{});
        return error.DivisionByZero;
    }

    const cos_theta = dot / denom;
    const angle = std.math.acos(std.math.clamp(cos_theta, -1.0, 1.0));

    return .{
        .number = angle,
    };
}

pub fn vectorCross(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();

    var other_val = (try expectValues(args, env, 1, "vector", "project"))[0];
    const other = try expectVector(&other_val, "vector", "cross");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = other.vector;

    if (a.items.len != 3 or b.items.len != 3) {
        try writer_err.print("vector.cross(other_vec) is only defined for 3D vectors\n", .{});
        return error.VectorSizeMismatch;
    }

    const result = [_]f64{
        a.items[1] * b.items[2] - a.items[2] * b.items[1],
        a.items[2] * b.items[0] - a.items[0] * b.items[2],
        a.items[0] * b.items[1] - a.items[1] * b.items[0],
    };

    for (a.items, 0..) |_, i| {
        a.items[i] = result[i];
    }

    return this.*;
}

pub fn vectorEquals(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    var other_val = (try expectValues(args, env, 1, "vector", "project"))[0];
    const other = try expectVector(&other_val, "vector", "equals");

    const inst = try getVectorInstance(this);
    const a = inst.vector;
    const b = other.vector;

    if (a.items.len != b.items.len) {
        return .{
            .boolean = false,
        };
    }

    for (a.items, b.items) |x, y| {
        if (x != y) return .{
            .boolean = false,
        };
    }

    return .{
        .boolean = true,
    };
}

pub fn vectorSet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectNumberArgs(args, env, 2, "vector", "set");
    const index_val = parts[0];
    const val_val = parts[1];
    const index: usize = @intFromFloat(index_val);

    const inst = try getVectorInstance(this);
    inst.vector.items[index] = val_val;
    return this.*;
}

pub fn vectorGet(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const index_val = (try expectNumberArgs(args, env, 1, "vector", "get"))[0];
    const index: usize = @intFromFloat(index_val);

    const inst = try getVectorInstance(this);
    if (index >= inst.vector.items.len) {
        try writer_err.print("vector.get(index): index {d} out of bounds for vector of length {d}\n", .{ index, inst.vector.items.len });
        return error.IndexOutOfBounds;
    }

    return .{
        .number = inst.vector.items[index],
    };
}

pub fn vectorSize(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "vector", "size");

    const inst = try getVectorInstance(this);
    return .{
        .number = @floatFromInt(inst.vector.items.len),
    };
}

pub fn vectorItems(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "vector", "items");

    const inst = try getVectorInstance(this);
    var result = std.ArrayList(Value).init(env.allocator);

    for (inst.vector.items) |item| {
        try result.append(.{
            .number = item,
        });
    }
    return .{
        .array = result,
    };
}

pub fn vectorStr(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "vector", "str");

    const inst = try getVectorInstance(this);
    return .{
        .string = try toString(env.allocator, inst.vector),
    };
}

pub fn toString(allocator: std.mem.Allocator, vector: std.ArrayList(f64)) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try result.append('[');
    for (vector.items, 0..) |item, i| {
        try result.appendSlice(try std.fmt.allocPrint(allocator, "{d}", .{item}));
        if (i != vector.items.len - 1) {
            try result.appendSlice(", ");
        }
    }
    try result.append(']');

    return try result.toOwnedSlice();
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "vector_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    const source =
        \\import vector;
        \\let v = new vector(1.0, 2.0, 3.0);
        \\let original = v.str();
        \\v.add(new vector(3.0, 2.0, 1.0));
        \\let added = v.str();
        \\v.sub(new vector(1.0, 1.0, 1.0));
        \\let subbed = v.str();
        \\v.scale(2.0);
        \\let scaled = v.str();
        \\let norm = v.norm();
        \\let angle = v.angle(new vector(0.0, 0.0, 1.0));
        \\let dot = v.dot(new vector(0.0, 0.0, 1.0));
        \\let equals_true = v.equals(new vector(6.0, 6.0, 6.0));
        \\let equals_false = v.equals(new vector(4.0, 2.0, 6.0));
        \\let cross = (new vector(1.0, 0.0, 0.0)).cross(new vector(0.0, 1.0, 0.0));
        \\let cross_str = cross.str();
        \\let dim = v.size();
        \\v.set(0, 10.0);
        \\let first = v.get(0);
        \\let items = v.items();
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const original = try env.get("original");
    const added = try env.get("added");
    const subbed = try env.get("subbed");
    const scaled = try env.get("scaled");
    const norm = try env.get("norm");
    const angle = try env.get("angle");
    const dot = try env.get("dot");
    const equals_true = try env.get("equals_true");
    const equals_false = try env.get("equals_false");
    const cross_str = try env.get("cross_str");
    const dim = try env.get("dim");
    const first = try env.get("first");
    const items = try env.get("items");

    try testing.expectEqualStrings("[1, 2, 3]", original.string);
    try testing.expectEqualStrings("[4, 4, 4]", added.string);
    try testing.expectEqualStrings("[3, 3, 3]", subbed.string);
    try testing.expectEqualStrings("[6, 6, 6]", scaled.string);
    try testing.expectApproxEqAbs(@as(f64, 10.3923), norm.number, 1e-3);
    try testing.expect(dot.number > 0);
    try testing.expect(angle.number >= 0);
    try testing.expectEqual(@as(bool, true), equals_true.boolean);
    try testing.expectEqual(@as(bool, true), !equals_false.boolean);
    try testing.expectEqualStrings("[0, 0, 1]", cross_str.string);
    try testing.expectEqual(@as(f64, 3.0), dim.number);
    try testing.expectEqual(@as(f64, 10.0), first.number);
    try testing.expect(items.array.items.len == 3);
}
