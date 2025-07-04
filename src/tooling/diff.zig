const std = @import("std");

const MIN_BUFFER = 1024;

pub fn compareBytes(allocator: std.mem.Allocator, names: [][:0]u8, files: []*std.fs.File, writer_err: std.io.AnyWriter) !void {
    if (names.len != files.len) {
        try writer_err.print("Names array was length {d} but files array was length {d}\n", .{names.len, files.len});
        return error.MalformedArrayLengths;
    }
    var stats = try std.ArrayList(std.fs.File.Stat).initCapacity(allocator, files.len);
    defer stats.deinit();

    var readers = try std.ArrayList(std.fs.File.Reader).initCapacity(allocator, files.len);
    defer readers.deinit();

    for (files) |file| {
        try stats.append(try file.stat());
        try readers.append(file.reader());
    }

    const diff_reader = readers.items[0];
    var idx: usize = 0;
    outer: while (true) : (idx += 1) {
        const min_size: usize = @min(stats.items[0].size, stats.items[idx].size, MIN_BUFFER);   
        const diff_buffer = try allocator.alloc(u8, min_size);
        defer allocator.free(diff_buffer);
        diff_reader.readNoEof(diff_buffer) catch break;

        for (readers.items[1..], 1..) |comp_reader, i| {
            const comp_buffer = try allocator.alloc(u8, min_size);
            defer allocator.free(comp_buffer);
            comp_reader.readNoEof(comp_buffer) catch break :outer;

            if (!std.mem.eql(u8, diff_buffer, comp_buffer)) {
                try writer_err.print("File {s} ({d}) differs from file {s} ({d}):\n", .{names[0], 0, names[i], i});
                try writer_err.print("Slice of File {s}:\n{s}\n\n", .{names[0], diff_buffer});
                try writer_err.print("Slice of File {s}:\n{s}\n", .{names[i], comp_buffer});
                return;
            }
        }
    }

    const size_compare = equalStats(stats.items);
    if (!size_compare.result) {
        try writer_err.print("File {s} differs from file {s}:\n", .{names[size_compare.diff], names[size_compare.first_invalid]});
        try writer_err.print("  Size of File {s}:\n{d}\n", .{names[size_compare.diff], stats.items[size_compare.diff].size});
        try writer_err.print("  Size of File {s}:\n{d}\n", .{names[size_compare.first_invalid], stats.items[size_compare.first_invalid].size});
        return;
    }
}

const StatCompareResult = struct {
    diff: usize = 0,
    first_invalid: usize = 0,
    result: bool,
};

fn equalStats(stats: []std.fs.File.Stat) StatCompareResult {
    var size: ?usize = null;
    for (stats, 0..) |stat, i| {
        if (size) |s| {
            if (s != stat.size) {
                return StatCompareResult{
                    .first_invalid = i,
                    .result = false,
                };
            }
        } else {
            size = @intCast(stat.size);
        }
    }
    return StatCompareResult{
        .result = true,
    };
}
