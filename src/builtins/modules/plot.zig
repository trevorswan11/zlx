const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const plot_helpers = @import("../helpers/plot.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;
const expectArrayArgs = builtins.expectArrayArgs;
const expectNumberArrays = builtins.expectNumberArrays;

var stored_xs: ?[]const f64 = null;
var stored_ys: ?[]const f64 = null;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "plot", plotHandler);
    try pack(&map, "show", showHandler);

    return .{ .object = map };
}

fn plotHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const parts = try expectArrayArgs(args, env, 2, "plot", "plot");
    const float_arrays = try expectNumberArrays(env.allocator, parts, "plot", "plot");

    if (float_arrays[0].len != float_arrays[1].len) {
        try writer_err.print("plot.plot(x, y): x and y arrays must have same length\n", .{});
        return error.InvalidArgument;
    }

    stored_xs = float_arrays[0];
    stored_ys = float_arrays[1];

    return .nil;
}

fn showHandler(_: []const *ast.Expr, _: *Environment) !Value {
    if (stored_xs == null or stored_ys == null) {
        return error.MissingPlotData;
    }

    try plot_helpers.renderPlot(stored_xs.?, stored_ys.?);
    return .nil;
}