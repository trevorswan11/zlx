const std = @import("std");
const parser = @import("parser/parser.zig");

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const buffer = try allocator.alloc(u8, stat.size);
    _ = try file.readAll(buffer);
    return buffer;
}

pub fn main() !void {
    const t0 = std.time.nanoTimestamp();
    const allocator = std.heap.page_allocator;
    const contents = try readFile(allocator, "examples/test.lang");
    defer allocator.free(contents);

    _ = try parser.parse(allocator, contents);
    const t1 = std.time.nanoTimestamp();
    std.debug.print("Parsing took: {d} ms", .{@as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0});
}
