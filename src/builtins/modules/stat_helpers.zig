const std = @import("std");

const FloatContext = struct {
    pub fn hash(_: @This(), v: f64) u64 {
        return @bitCast(v);
    }

    pub fn eql(_: @This(), a: f64, b: f64) bool {
        return a == b;
    }
};

/// The mean value of an array of floats
pub fn mean(values: []const f64) f64 {
    var sum: f64 = 0;
    for (values) |v| {
        sum += v;
    }
    return if (values.len > 0) sum / @as(f64, @floatFromInt(values.len)) else 0;
}

/// The min value of an array of floats
pub fn min(values: []const f64) f64 {
    if (values.len == 0) return 0;
    var result = values[0];
    for (values[1..]) |v| {
        if (v < result) {
            result = v;
        }
    }
    return result;
}

/// The max value of an array of floats
pub fn max(values: []const f64) f64 {
    if (values.len == 0) return 0;
    var result = values[0];
    for (values[1..]) |v| {
        if (v > result) {
            result = v;
        }
    }
    return result;
}

/// The range of an array of floats
pub fn range(values: []const f64) f64 {
    return max(values) - min(values);
}

/// The variance of data assumed to be from a population
pub fn variancePopulation(values: []const f64) f64 {
    const mu = mean(values);
    var sum: f64 = 0;
    for (values) |v| {
        sum += (v - mu) * (v - mu);
    }
    return if (values.len > 0) sum / @as(f64, @floatFromInt(values.len)) else 0;
}

/// The variance of data assumed to be from a sample
pub fn varianceSample(values: []const f64) f64 {
    const mu = mean(values);
    var sum: f64 = 0;
    for (values) |v| {
        sum += (v - mu) * (v - mu);
    }
    return if (values.len > 1) sum / @as(f64, @floatFromInt(values.len - 1)) else 0;
}

/// The stddev of data assumed to be from a population
pub fn stddevPopulation(values: []const f64) f64 {
    return @sqrt(variancePopulation(values));
}

/// The variance of data assumed to be from a sample
pub fn stddevSample(values: []const f64) f64 {
    return @sqrt(varianceSample(values));
}

/// The median value of an array of floats
pub fn median(allocator: std.mem.Allocator, values: []const f64) !f64 {
    if (values.len == 0) return 0;
    const sorted = try allocator.alloc(f64, values.len);
    defer allocator.free(sorted);
    std.mem.copyForwards(f64, sorted, values);
    std.sort.insertion(f64, sorted, {}, std.sort.asc(f64));

    const mid = values.len / 2;
    if (values.len % 2 == 0) {
        return (sorted[mid - 1] + sorted[mid]) / 2.0;
    } else {
        return sorted[mid];
    }
}

/// The most common value of an array of floats
pub fn mode(allocator: std.mem.Allocator, values: []const f64) !f64 {
    var freq = std.HashMap(f64, usize, FloatContext, 80).init(allocator);
    defer freq.deinit();

    for (values) |v| {
        const count = freq.get(v) orelse 0;
        try freq.put(v, count + 1);
    }

    var max_val: f64 = 0;
    var max_count: usize = 0;

    var iter = freq.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* > max_count) {
            max_val = entry.key_ptr.*;
            max_count = entry.value_ptr.*;
        }
    }

    return max_val;
}

/// The covariance of data assumed to be from a sample
pub fn covariancePopulation(x: []const f64, y: []const f64) f64 {
    if (x.len != y.len or x.len == 0) {
        return 0;
    }
    const mean_x = mean(x);
    const mean_y = mean(y);

    var sum: f64 = 0;
    for (x, 0..) |xi, i| {
        sum += (xi - mean_x) * (y[i] - mean_y);
    }
    return sum / @as(f64, @floatFromInt(x.len));
}

/// The covariance of data assumed to be from a sample
pub fn covarianceSample(x: []const f64, y: []const f64) f64 {
    if (x.len != y.len or x.len == 0) {
        return 0;
    }
    const mean_x = mean(x);
    const mean_y = mean(y);

    var sum: f64 = 0;
    for (x, 0..) |xi, i| {
        sum += (xi - mean_x) * (y[i] - mean_y);
    }
    return sum / @as(f64, @floatFromInt(x.len - 1));
}

/// The correlation of data assumed to be from a sample
pub fn correlationPopulation(x: []const f64, y: []const f64) f64 {
    const std_x = stddevPopulation(x);
    const std_y = stddevPopulation(y);
    if (std_x == 0 or std_y == 0) {
        return 0;
    }

    return covariancePopulation(x, y) / (std_x * std_y);
}

/// The correlation of data assumed to be from a sample
pub fn correlationSample(x: []const f64, y: []const f64) f64 {
    const std_x = stddevSample(x);
    const std_y = stddevSample(y);
    if (std_x == 0 or std_y == 0) {
        return 0;
    }

    return covarianceSample(x, y) / (std_x * std_y);
}

/// Packed data for linear regression analysis results
pub const RegressionResult = struct {
    const Self = @This();

    slope: f64,
    intercept: f64,
    r_squared: f64,

    pub fn predict(self: *Self, x: f64) f64 {
        return self.slope * x + self.intercept;
    }
};

/// The linear regression result of data assumed to be from a sample
pub fn linearRegressionPopulation(x: []const f64, y: []const f64) RegressionResult {
    const cov = covariancePopulation(x, y);
    const var_x = variancePopulation(x);
    const slope = if (var_x == 0) 0 else cov / var_x;
    const intercept = mean(y) - slope * mean(x);
    const r = correlationPopulation(x, y);

    return RegressionResult{
        .slope = slope,
        .intercept = intercept,
        .r_squared = r * r,
    };
}

/// The linear regression result of data assumed to be from a sample
pub fn linearRegressionSample(x: []const f64, y: []const f64) RegressionResult {
    const cov = covarianceSample(x, y);
    const var_x = variancePopulation(x);
    const slope = if (var_x == 0) 0 else cov / var_x;
    const intercept = mean(y) - slope * mean(x);
    const r = correlationSample(x, y);

    return RegressionResult{
        .slope = slope,
        .intercept = intercept,
        .r_squared = r * r,
    };
}

/// The error function, solved numerically for probability distributions (gaussian)
fn erf(x: f64) f64 {
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    const sign: f64 = if (x < 0) -1.0 else 1.0;
    const abs_x = @abs(x);

    const t = 1.0 / (1.0 + p * abs_x);
    const y = 1.0 - (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t) * @exp(-abs_x * abs_x);

    return sign * y;
}

/// The z-score of an input relative to the input mean and std
pub fn z_score(x: f64, mu: f64, sigma: f64) f64 {
    if (sigma == 0) {return 0;}
    return (x - mu) / sigma;
}

/// The normal probability distribution function
pub fn normal_pdf(x: f64, mu: f64, sigma: f64) f64 {
    const sqrt2pi = 2.5066282746310002; // ≈ sqrt(2π)
    const z = z_score(x, mu, sigma);
    return (@exp(-0.5 * z * z)) / (sigma * sqrt2pi);
}

/// The normal cumulative distribution function
pub fn normal_cdf(x: f64, mu: f64, sigma: f64) f64 {
    const z = (x - mu) / (sigma * @sqrt(2.0));
    return 0.5 * (1.0 + erf(z));
}

/// The normal probability distribution function with mean 0 and std 1
pub fn standard_normal_pdf(x: f64) f64 {
    return normal_pdf(x, 0.0, 1.0);
}

/// The normal cumulative distribution function with mean 0 and std 1
pub fn standard_normal_cdf(x: f64) f64 {
    return normal_cdf(x, 0.0, 1.0);
}

pub fn z_test(sample_mean: f64, population_mean: f64, stddev: f64, n: usize) f64 {
    if (stddev == 0 or n == 0) {return 0;}
    const se = stddev / @sqrt(@as(f64, @floatFromInt(n)));
    return (sample_mean - population_mean) / se;
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "mean" {
    const data = [_]f64{ 2.0, 4.0, 6.0, 8.0 };
    try testing.expectEqual(@as(f64, 5.0), mean(data[0..]));
}

test "min and max" {
    const data = [_]f64{ 7.0, 2.0, 5.0, 9.0 };
    try testing.expectEqual(@as(f64, 2.0), min(data[0..]));
    try testing.expectEqual(@as(f64, 9.0), max(data[0..]));
}

test "range" {
    const data = [_]f64{ 3.0, 6.0, 9.0 };
    try testing.expectEqual(@as(f64, 6.0), range(data[0..]));
}

test "variance and stddev" {
    const data = [_]f64{ 2.0, 4.0, 6.0 };

    try testing.expectApproxEqAbs(@as(f64, 2.6666667), variancePopulation(data[0..]), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 4.0), varianceSample(data[0..]), 1e-6);

    try testing.expectApproxEqAbs(@as(f64, 1.6329931), stddevPopulation(data[0..]), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 2.0), stddevSample(data[0..]), 1e-6);
}

test "median (odd and even length)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const odd = [_]f64{ 3.0, 1.0, 2.0 };
    const even = [_]f64{ 5.0, 3.0, 1.0, 2.0 };

    try testing.expectEqual(@as(f64, 2.0), try median(allocator, odd[0..]));
    try testing.expectEqual(@as(f64, 2.5), try median(allocator, even[0..]));
}

test "mode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const data = [_]f64{ 1.0, 2.0, 2.0, 3.0, 3.0, 3.0 };
    try testing.expectEqual(@as(f64, 3.0), try mode(allocator, data[0..]));
}

test "covariance: sample vs population" {
    const x = [_]f64{ 2.0, 4.0, 6.0 };
    const y = [_]f64{ 3.0, 6.0, 9.0 };

    try testing.expectApproxEqAbs(@as(f64, 4.0), covariancePopulation(x[0..], y[0..]), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 6.0), covarianceSample(x[0..], y[0..]), 1e-6);
}

test "correlation (perfect linear)" {
    const x = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const y = [_]f64{ 2.0, 4.0, 6.0, 8.0, 10.0 };

    try testing.expectApproxEqAbs(@as(f64, 1.0), correlationPopulation(x[0..], y[0..]), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 1.0), correlationSample(x[0..], y[0..]), 1e-6);
}

test "correlation (zero correlation)" {
    const x = [_]f64{ 1.0, 2.0, 3.0 };
    const y = [_]f64{ 4.0, 4.0, 4.0 };
    try testing.expectApproxEqAbs(@as(f64, 0.0), correlationPopulation(x[0..], y[0..]), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.0), correlationSample(x[0..], y[0..]), 1e-6);
}

test "linear regression: sample vs population distinction" {
    const x = [_]f64{ 2.0, 4.0, 6.0 };
    const y = [_]f64{ 3.0, 6.0, 9.0 };

    const pop = linearRegressionPopulation(x[0..], y[0..]);
    try testing.expectApproxEqAbs(@as(f64, 1.5), pop.slope, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.0), pop.intercept, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 1.0), pop.r_squared, 1e-6);

    const sample = linearRegressionSample(x[0..], y[0..]);
    try testing.expectApproxEqAbs(@as(f64, 2.25), sample.slope, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, -3.0), sample.intercept, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 1.0), sample.r_squared, 1e-6);
}

test "linear regression: constant Y" {
    const x = [_]f64{ 1.0, 2.0, 3.0 };
    const y = [_]f64{ 5.0, 5.0, 5.0 };

    var pop = linearRegressionPopulation(x[0..], y[0..]);
    try testing.expectApproxEqAbs(@as(f64, 0.0), pop.slope, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 5.0), pop.intercept, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.0), pop.r_squared, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 5.0), pop.predict(100.0), 1e-6);

    var sample = linearRegressionSample(x[0..], y[0..]);
    try testing.expectApproxEqAbs(@as(f64, 0.0), sample.slope, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 5.0), sample.intercept, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.0), sample.r_squared, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 5.0), sample.predict(100.0), 1e-6);
}

test "z_score" {
    try testing.expectApproxEqAbs(@as(f64, 1.0), z_score(6.0, 5.0, 1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, -1.0), z_score(4.0, 5.0, 1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.0), z_score(5.0, 5.0, 1.0), 1e-6);
}

test "standard_normal_pdf" {
    try testing.expectApproxEqAbs(@as(f64, 0.39894228), standard_normal_pdf(0.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.24197072), standard_normal_pdf(1.0), 1e-6);
}

test "standard_normal_cdf" {
    try testing.expectApproxEqAbs(@as(f64, 0.5), standard_normal_cdf(0.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.8413447), standard_normal_cdf(1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.1586553), standard_normal_cdf(-1.0), 1e-6);
}

test "normal_pdf (non-standard)" {
    try testing.expectApproxEqAbs(@as(f64, 0.39894228), normal_pdf(5.0, 5.0, 1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.24197072), normal_pdf(6.0, 5.0, 1.0), 1e-6);
}

test "normal_cdf (non-standard)" {
    try testing.expectApproxEqAbs(@as(f64, 0.5), normal_cdf(5.0, 5.0, 1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.8413447), normal_cdf(6.0, 5.0, 1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.1586553), normal_cdf(4.0, 5.0, 1.0), 1e-6);
}

test "z_test" {
    // sample mean = 105, population mean = 100, stddev = 15, n = 25
    // z = (105 - 100) / (15 / sqrt(25)) = 5 / 3 = 1.666...
    try testing.expectApproxEqAbs(@as(f64, 1.6666667), z_test(105.0, 100.0, 15.0, 25), 1e-6);

    // Should return 0 for edge cases
    try testing.expectApproxEqAbs(@as(f64, 0.0), z_test(105.0, 100.0, 0.0, 25), 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 0.0), z_test(105.0, 100.0, 15.0, 0), 1e-6);
}
