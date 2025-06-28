const std = @import("std");
const raylib = @import("raylib");

pub const Options = struct {
    allocator: std.mem.Allocator,

    grid: bool,
    window_title: ?[]const u8,
    plot_title: ?[]const u8,
    title_font_size: i32 = 40,
    x_axis_font_size: i32 = 20,
    x_axis_label: ?[]const u8 = null,
    y_axis_font_size: i32 = 20,
    y_axis_label: ?[]const u8 = null,
};

pub fn renderPlot(
    allocator: std.mem.Allocator,
    xs: []const f64,
    ys: []const f64,
    opts: Options,
) !void {
    const width = 800;
    const height = 600;
    const margin: i32 = if (opts.title_font_size <= 20) 50 else 100;

    raylib.setTraceLogLevel(.fatal);
    const application_title = if (opts.window_title) |t| blk: {
        break :blk try toNullTerminatedString(allocator, t);
    } else blk: {
        break :blk try toNullTerminatedString(allocator, "ZLX");
    };

    raylib.initWindow(width, height, application_title);
    raylib.setTargetFPS(60);

    while (!raylib.windowShouldClose()) {
        raylib.beginDrawing();
        defer raylib.endDrawing();

        raylib.clearBackground(.white);
        try drawTitle(allocator, opts.plot_title, width, margin, opts);
        try drawAxes(width, height, margin, opts);

        // Opts
        if (opts.grid) {
            drawGrid(width, height, margin);
        }

        try drawLine(xs, ys, width, height, margin);
    }

    raylib.closeWindow();
}

fn drawAxes(w: i32, h: i32, margin: i32, _: Options) !void {
    // Draw X and Y axes
    raylib.drawLine(margin, h - margin, w - margin, h - margin, .black); // X axis
    raylib.drawLine(margin, h - margin, margin, margin, .black); // Y axis
}

fn drawTitle(allocator: std.mem.Allocator, title: ?[]const u8, w: i32, margin: i32, opts: Options) !void {
    const font_size = opts.title_font_size;
    const title_string = if (title) |t| blk: {
        break :blk try toNullTerminatedString(allocator, t);
    } else blk: {
        break :blk try toNullTerminatedString(allocator, "");
    };
    raylib.drawText(
        title_string,
        @divFloor((w - raylib.measureText(title_string, font_size)), 2),
        @divFloor(margin, 2),
        font_size,
        .black,
    );
}

fn drawGrid(w: i32, h: i32, margin: i32) void {
    const grid_step = 50;

    // Draw vertical grid lines
    var x = margin + grid_step;
    while (x < w - margin) {
        raylib.drawLine(x, margin, x, h - margin, .light_gray);
        x += grid_step;
    }

    // Draw horizontal grid lines
    var y = margin + grid_step;
    while (y < h - margin) {
        raylib.drawLine(margin, y, w - margin, y, .light_gray);
        y += grid_step;
    }
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
            .blue,
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

fn toNullTerminatedString(allocator: std.mem.Allocator, input: []const u8) ![:0]const u8 {
    var buffer = try allocator.alloc(u8, input.len + 1);
    for (input, 0..) |c, i| {
        buffer[i] = c;
    }
    buffer[input.len] = 0;
    return buffer[0..input.len :0];
}
