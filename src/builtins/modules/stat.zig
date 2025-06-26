const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const statistics = @import("../helpers/statistics.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectNumberArrays = builtins.expectNumberArrays;

const flags = struct {
    const population: f64 = 0.0;
    const sample: f64 = 1.0;
};

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    // Population/Sample 'enum' values
    try map.put("population", .{
        .number = flags.population,
    });
    try map.put("sample", .{
        .number = flags.sample,
    });

    // Packed functions
    try pack(&map, "mean", meanHandler);
    try pack(&map, "min", minHandler);
    try pack(&map, "max", maxHandler);
    try pack(&map, "range", rangeHandler);
    try pack(&map, "variance", varianceHandler);
    try pack(&map, "stddev", stddevHandler);
    try pack(&map, "median", medianHandler);
    try pack(&map, "mode", modeHandler);
    try pack(&map, "covariance", covarianceHandler);
    try pack(&map, "correlation", correlationHandler);
    try pack(&map, "linear_regression", linearRegressionHandler);
    try pack(&map, "z_score", zScoreHandler);
    try pack(&map, "normal_cdf", normalCdfHandler);
    try pack(&map, "normal_pdf", normalPdfHandler);

    return .{
        .object = map,
    };
}

fn meanHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectArrayArgs(args, env, 1, "stat", "mean");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "mean"))[0];

    return .{
        .number = statistics.mean(float_array),
    };
}

fn medianHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectArrayArgs(args, env, 1, "stat", "median");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "median"))[0];

    return .{
        .number = try statistics.median(env.allocator, float_array),
    };
}

fn modeHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectArrayArgs(args, env, 1, "stat", "mode");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "mode"))[0];
    const result = statistics.mode(env.allocator, float_array) catch |err| switch (err) {
        error.NoMode => return .nil,
        else => return err,
    };

    return .{
        .number = result,
    };
}

fn minHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectArrayArgs(args, env, 1, "stat", "min");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "min"))[0];

    return .{
        .number = statistics.min(float_array),
    };
}

fn maxHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectArrayArgs(args, env, 1, "stat", "max");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "max"))[0];

    return .{
        .number = statistics.max(float_array),
    };
}

fn rangeHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectArrayArgs(args, env, 1, "stat", "range");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "range"))[0];

    return .{
        .number = statistics.range(float_array),
    };
}

fn varianceHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("stat module: variance expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const parts = try expectArrayArgs(args[0..1], env, 1, "stat", "variance");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "variance"))[0];
    const population = (try expectNumberArgs(args[1..], env, 1, "stat", "variance"))[0] == flags.population;

    return .{
        .number = if (population) blk: {
            break :blk statistics.variancePopulation(float_array);
        } else blk: {
            break :blk statistics.varianceSample(float_array);
        },
    };
}

fn stddevHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 2) {
        try writer_err.print("stat module: stddev expects 2 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const parts = try expectArrayArgs(args[0..1], env, 1, "stat", "stddev");
    const float_array = (try expectNumberArrays(env.allocator, parts, "stat", "stddev"))[0];
    const population = (try expectNumberArgs(args[1..], env, 1, "stat", "stddev"))[0] == flags.population;

    return .{
        .number = if (population) blk: {
            break :blk statistics.stddevPopulation(float_array);
        } else blk: {
            break :blk statistics.stddevSample(float_array);
        },
    };
}

fn covarianceHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("stat module: covariance expects 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const arr_parts = try expectArrayArgs(args[0..2], env, 2, "stat", "covariance");
    const float_arrays = try expectNumberArrays(env.allocator, arr_parts, "stat", "covariance");
    const population = (try expectNumberArgs(args[2..], env, 1, "stat", "covariance"))[0] == flags.population;

    return .{
        .number = if (population) blk: {
            break :blk statistics.covariancePopulation(float_arrays[0], float_arrays[1]);
        } else blk: {
            break :blk statistics.covarianceSample(float_arrays[0], float_arrays[1]);
        },
    };
}

fn correlationHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("stat module: correlation expects 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const arr_parts = try expectArrayArgs(args[0..2], env, 2, "stat", "correlation");
    const float_arrays = try expectNumberArrays(env.allocator, arr_parts, "stat", "correlation");
    const population = (try expectNumberArgs(args[2..], env, 1, "stat", "correlation"))[0] == flags.population;

    return .{
        .number = if (population) blk: {
            break :blk statistics.correlationPopulation(float_arrays[0], float_arrays[1]);
        } else blk: {
            break :blk statistics.correlationSample(float_arrays[0], float_arrays[1]);
        },
    };
}

fn linearRegressionHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 3) {
        try writer_err.print("stat module: linear_regression expects 3 arguments, got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const arr_parts = try expectArrayArgs(args[0..2], env, 2, "stat", "linear_regression");
    const float_arrays = try expectNumberArrays(env.allocator, arr_parts, "stat", "linear_regression");
    const population = (try expectNumberArgs(args[2..], env, 1, "stat", "linear_regression"))[0] == flags.population;
    const result = if (population) blk: {
        break :blk statistics.linearRegressionPopulation(float_arrays[0], float_arrays[1]);
    } else blk: {
        break :blk statistics.linearRegressionSample(float_arrays[0], float_arrays[1]);
    };

    var obj = std.StringHashMap(Value).init(env.allocator);
    try obj.put("slope", .{
        .number = result.slope,
    });
    try obj.put("intercept", .{
        .number = result.intercept,
    });
    try obj.put("r_squared", .{
        .number = result.r_squared,
    });

    return .{
        .object = obj,
    };
}

fn zScoreHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const parts = try expectNumberArgs(args, env, 3, "stat", "z_score");

    return .{
        .number = statistics.zScore(parts[0], parts[1], parts[2]),
    };
}

fn normalPdfHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 1) {
        const num = (try expectNumberArgs(args, env, 1, "stat", "normal_pdf"))[0];
        return .{
            .number = statistics.standardNormalPdf(num),
        };
    } else if (args.len == 3) {
        const parts = try expectNumberArgs(args, env, 3, "stat", "normal_pdf");
        return .{
            .number = statistics.normalPdf(parts[0], parts[1], parts[2]),
        };
    } else {
        try writer_err.print("stat module: normal_pdf expects 1 or 3 arguments, got {d}", .{args.len});
        return error.ArgumentCountMismatch;
    }
}

fn normalCdfHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len == 1) {
        const num = (try expectNumberArgs(args, env, 1, "stat", "normal_cdf"))[0];
        return .{
            .number = statistics.standardNormalCdf(num),
        };
    } else if (args.len == 3) {
        const parts = try expectNumberArgs(args, env, 3, "stat", "normal_pdf");
        return .{
            .number = statistics.normalCdf(parts[0], parts[1], parts[2]),
        };
    } else {
        try writer_err.print("stat module: normal_cdf expects 1 or 3 arguments, got {d}", .{args.len});
        return error.ArgumentCountMismatch;
    }
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "stat_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriters(writer);

    const source =
        \\import stat;
        \\
        \\println(stat.mean([2.0, 4.0, 6.0, 8.0]));
        \\println(stat.min([7.0, 2.0, 5.0, 9.0]));
        \\println(stat.max([7.0, 2.0, 5.0, 9.0]));
        \\println(stat.range([3.0, 6.0, 9.0]));
        \\
        \\println(stat.variance([2.0, 4.0, 6.0], stat.population));
        \\println(stat.variance([2.0, 4.0, 6.0], stat.sample));
        \\
        \\println(stat.stddev([2.0, 4.0, 6.0], stat.population));
        \\println(stat.stddev([2.0, 4.0, 6.0], stat.sample));
        \\
        \\println(stat.median([3.0, 1.0, 2.0]));
        \\println(stat.median([5.0, 3.0, 1.0, 2.0]));
        \\
        \\println(stat.mode([1.0, 2.0, 2.0, 3.0, 3.0, 3.0]));
        \\
        \\println(stat.covariance([2.0, 4.0, 6.0], [3.0, 6.0, 9.0], stat.population));
        \\println(stat.covariance([2.0, 4.0, 6.0], [3.0, 6.0, 9.0], stat.sample));
        \\
        \\println(stat.correlation([1.0, 2.0, 3.0], [4.0, 4.0, 4.0], stat.population));
        \\println(stat.correlation([1.0, 2.0, 3.0], [4.0, 4.0, 4.0], stat.sample));
        \\
        \\let lr_pop = stat.linear_regression([2.0, 4.0, 6.0], [3.0, 6.0, 9.0], stat.population);
        \\println(lr_pop.slope, lr_pop.intercept, lr_pop.r_squared);
        \\
        \\let lr_sample = stat.linear_regression([2.0, 4.0, 6.0], [3.0, 6.0, 9.0], stat.sample);
        \\println(lr_sample.slope, lr_sample.intercept, lr_sample.r_squared);
        \\
        \\let lr_flat = stat.linear_regression([1.0, 2.0, 3.0], [5.0, 5.0, 5.0], stat.population);
        \\println(lr_flat.slope, lr_flat.intercept, lr_flat.r_squared);
        \\
        \\let lr_flat_s = stat.linear_regression([1.0, 2.0, 3.0], [5.0, 5.0, 5.0], stat.sample);
        \\println(lr_flat_s.slope, lr_flat_s.intercept, lr_flat_s.r_squared);
        \\
        \\println(stat.z_score(6.0, 5.0, 1.0));
        \\println(stat.z_score(4.0, 5.0, 1.0));
        \\println(stat.z_score(5.0, 5.0, 1.0));
        \\
        \\println(stat.normal_pdf(0.0));
        \\println(stat.normal_pdf(1.0));
        \\
        \\println(stat.normal_cdf(0.0));
        \\println(stat.normal_cdf(1.0));
        \\println(stat.normal_cdf(-1.0));
        \\
        \\println(stat.normal_pdf(5.0, 5.0, 1.0));
        \\println(stat.normal_pdf(6.0, 5.0, 1.0));
        \\
        \\println(stat.normal_cdf(5.0, 5.0, 1.0));
        \\println(stat.normal_cdf(6.0, 5.0, 1.0));
        \\println(stat.normal_cdf(4.0, 5.0, 1.0));
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    var lines = std.mem.tokenizeScalar(u8, output_buffer.items, '\n');
    const epsilon = 1e-6;
    const expected: []const f64 = &.{
        5.0, // mean
        2.0, // min
        9.0, // max
        6.0, // range
        2.6666667, // variance (population)
        4.0, // variance (sample)
        1.6329931, // stddev (population)
        2.0, // stddev (sample)
        2.0, // median (odd)
        2.5, // median (even)
        3.0, // mode
        4.0, // covariance (population)
        6.0, // covariance (sample)
        0.0, // correlation (population, flat y)
        0.0, // correlation (sample, flat y)
        1.5, 0.0, 1.0, // linear regression (population): slope, intercept, r_squared
        2.25, -3.0, 1.0, // linear regression (sample): slope, intercept, r_squared
        0.0, 5.0, 0.0, // linear regression (population, flat): slope, intercept, r_squared
        0.0, 5.0, 0.0, // linear regression (sample, flat): slope, intercept, r_squared
        1.0, // z-score(6,5,1)
        -1.0, // z-score(4,5,1)
        0.0, // z-score(5,5,1)
        0.39894228, // normal_pdf(0)
        0.24197072, // normal_pdf(1)
        0.5, // normal_cdf(0)
        0.8413447, // normal_cdf(1)
        0.1586553, // normal_cdf(-1)
        0.39894228, // normal_pdf(5,5,1)
        0.24197072, // normal_pdf(6,5,1)
        0.5, // normal_cdf(5,5,1)
        0.8413447, // normal_cdf(6,5,1)
        0.1586553, // normal_cdf(4,5,1)
    };

    var i: usize = 0;
    while (lines.next()) |line| : (i += 1) {
        const actual = try std.fmt.parseFloat(f64, line);
        if (std.math.isNan(expected[i])) {
            try testing.expect(std.math.isNan(actual));
        } else {
            try testing.expectApproxEqAbs(expected[i], actual, epsilon);
        }
    }
}
