const std = @import("std");
const raylib = @import("raylib");

pub fn renderPlot(xs: []const f64, ys: []const f64) !void {
    const width = 800;
    const height = 600;
    const margin = 50;

    raylib.setTraceLogLevel(raylib.TraceLogLevel.fatal);
    raylib.initWindow(width, height, "Trial Plot");
    raylib.setTargetFPS(60);

    while (!raylib.windowShouldClose()) {
        raylib.beginDrawing();
        defer raylib.endDrawing();

        raylib.clearBackground(raylib.Color.white);
        drawAxes(width, height, margin);
        try drawLine(xs, ys, width, height, margin);
    }

    raylib.closeWindow();
}

fn drawAxes(w: i32, h: i32, margin: i32) void {
    raylib.drawLine(margin, h - margin, w - margin, h - margin, raylib.Color.black); // X axis
    raylib.drawLine(margin, h - margin, margin, margin, raylib.Color.black); // Y axis
}

fn drawLine(xs: []const f64, ys: []const f64, w: i32, h: i32, margin: i32) !void {
    const plot_width = w - 2 * margin;
    const plot_height = h - 2 * margin;

    const x_min = try min(xs);
    const x_max = try max(xs);
    const y_min = try min(ys);
    const y_max = try max(ys);

    for (xs, 0..) |x, i| {
        if (i + 1 >= xs.len) break;

        const x0 = scale(x, x_min, x_max, 0, @floatFromInt(plot_width));
        const y0 = scale(ys[i], y_min, y_max, @floatFromInt(plot_height), 0);
        const x1 = scale(xs[i + 1], x_min, x_max, 0, @floatFromInt(plot_width));
        const y1 = scale(ys[i + 1], y_min, y_max, @floatFromInt(plot_height), 0);

        raylib.drawLine(
            @intFromFloat(x0 + @as(f64, @floatFromInt(margin))),
            @intFromFloat(y0 + @as(f64, @floatFromInt(margin))),
            @intFromFloat(x1 + @as(f64, @floatFromInt(margin))),
            @intFromFloat(y1 + @as(f64, @floatFromInt(margin))),
            raylib.Color.blue,
        );
    }
}

fn scale(value: f64, in_min: f64, in_max: f64, out_min: f64, out_max: f64) f64 {
    return (value - in_min) / (in_max - in_min) * (out_max - out_min) + out_min;
}

fn min(vals: []const f64) !f64 {
    if (vals.len == 0) {
        return error.EmptyArray;
    }

    var minimum = vals[0];
    for (1..vals.len) |i| {
        if (minimum > vals[i]) {
            minimum = vals[i];
        }
    }
    return minimum;
}

fn max(vals: []const f64) !f64 {
    if (vals.len == 0) {
        return error.EmptyArray;
    }

    var maximum = vals[0];
    for (1..vals.len) |i| {
        if (maximum < vals[i]) {
            maximum = vals[i];
        }
    }
    return maximum;
}
