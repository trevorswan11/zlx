const std = @import("std");
const Value = @import("../../interpreter/interpreter.zig").Value;

pub fn loadConstants(map: *std.StringHashMap(Value)) !void {
    try map.put(
        "ns_per_us",
        .{
            .number = @floatFromInt(std.time.ns_per_us),
        },
    );
    try map.put(
        "ns_per_ms",
        .{
            .number = @floatFromInt(std.time.ns_per_ms),
        },
    );
    try map.put(
        "ns_per_s",
        .{
            .number = @floatFromInt(std.time.ns_per_s),
        },
    );
    try map.put(
        "ns_per_min",
        .{
            .number = @floatFromInt(std.time.ns_per_min),
        },
    );
    try map.put(
        "ns_per_hour",
        .{
            .number = @floatFromInt(std.time.ns_per_hour),
        },
    );
    try map.put(
        "ns_per_day",
        .{
            .number = @floatFromInt(std.time.ns_per_day),
        },
    );
    try map.put(
        "ns_per_week",
        .{
            .number = @floatFromInt(std.time.ns_per_week),
        },
    );

    try map.put(
        "us_per_ms",
        .{
            .number = @floatFromInt(std.time.us_per_ms),
        },
    );
    try map.put(
        "us_per_s",
        .{
            .number = @floatFromInt(std.time.us_per_s),
        },
    );
    try map.put(
        "us_per_min",
        .{
            .number = @floatFromInt(std.time.us_per_min),
        },
    );
    try map.put(
        "us_per_hour",
        .{
            .number = @floatFromInt(std.time.us_per_hour),
        },
    );
    try map.put(
        "us_per_day",
        .{
            .number = @floatFromInt(std.time.us_per_day),
        },
    );
    try map.put(
        "us_per_week",
        .{
            .number = @floatFromInt(std.time.us_per_week),
        },
    );

    try map.put(
        "ms_per_s",
        .{
            .number = @floatFromInt(std.time.ms_per_s),
        },
    );
    try map.put(
        "ms_per_min",
        .{
            .number = @floatFromInt(std.time.ms_per_min),
        },
    );
    try map.put(
        "ms_per_hour",
        .{
            .number = @floatFromInt(std.time.ms_per_hour),
        },
    );
    try map.put(
        "ms_per_day",
        .{
            .number = @floatFromInt(std.time.ms_per_day),
        },
    );
    try map.put(
        "ms_per_week",
        .{
            .number = @floatFromInt(std.time.ms_per_week),
        },
    );

    try map.put(
        "s_per_min",
        .{
            .number = @floatFromInt(std.time.s_per_min),
        },
    );
    try map.put(
        "s_per_hour",
        .{
            .number = @floatFromInt(std.time.s_per_hour),
        },
    );
    try map.put(
        "s_per_day",
        .{
            .number = @floatFromInt(std.time.s_per_day),
        },
    );
    try map.put(
        "s_per_week",
        .{
            .number = @floatFromInt(std.time.s_per_week),
        },
    );
}
