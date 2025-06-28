const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");
const plot_helpers = @import("../helpers/plotting.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;
const BuiltinModuleHandler = builtins.BuiltinModuleHandler;

const pack = builtins.pack;
const expectStringArgs = builtins.expectStringArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectNumberArrays = builtins.expectNumberArrays;

var stored_xs: ?[]const f64 = null;
var stored_ys: ?[]const f64 = null;
var plot_title: ?[]const u8 = null;
var window_title: ?[]const u8 = null;
var grid: bool = false;

pub fn load(allocator: std.mem.Allocator) !Value {
    var map = std.StringHashMap(Value).init(allocator);

    try pack(&map, "plot", plotHandler);
    try pack(&map, "title", plotTitleHandler);
    try pack(&map, "plot_title", plotTitleHandler);
    try pack(&map, "window_title", windowTitleHandler);
    try pack(&map, "grid", gridHandler);
    try pack(&map, "show", showHandler);

    return .{
        .object = map,
    };
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

fn windowTitleHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("plot.window_title(name) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const title = (try expectStringArgs(args, env, 1, "plot", "window_title"))[0];
    window_title = title;

    return .nil;
}

fn plotTitleHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 1) {
        try writer_err.print("plot.plot_title(name) expects 1 argument but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    const title = (try expectStringArgs(args, env, 1, "plot", "plot_title"))[0];
    plot_title = title;

    return .nil;
}

fn gridHandler(args: []const *ast.Expr, _: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("plot.grid() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    grid = !grid;

    return .nil;
}

fn showHandler(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    if (args.len != 0) {
        try writer_err.print("plot.show() expects 0 arguments but got {d}\n", .{args.len});
        return error.ArgumentCountMismatch;
    }

    if (stored_xs == null or stored_ys == null) {
        return error.MissingPlotData;
    }

    const opts = plot_helpers.Options{
        .allocator = env.allocator,
        .grid = grid,
        .plot_title = plot_title,
        .window_title = window_title,
    };

    try plot_helpers.renderPlot(
        env.allocator,
        stored_xs.?,
        stored_ys.?,
        opts,
    );
    return .nil;
}
