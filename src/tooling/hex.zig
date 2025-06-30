const std = @import("std");

pub fn dump(bytes: []const u8, writer_out: std.io.AnyWriter, writer_err: std.io.AnyWriter) !void {
    if (bytes.len == 0) {
        try writer_err.print("Hex Dump Error: File Empty!\n", .{});
        return error.EmptyFile;
    }

    // Get buffered writer for efficient printing
    var buf_out = std.io.bufferedWriter(writer_out);
    const buffer_writer = buf_out.writer();

    var i: usize = 0;
    while (i < bytes.len) : (i += 16) {
        // Print offset
        try buffer_writer.print("{x:0>8}: ", .{i});

        // Print hex values (16 per line)
        var j: usize = 0;
        while (j < 16) : (j += 1) {
            if (i + j < bytes.len) {
                try buffer_writer.print("{x:0>2} ", .{bytes[i + j]});
            } else {
                try buffer_writer.print("   ", .{});
            }
        }

        // Print ASCII representation
        try buffer_writer.print(" ", .{});
        j = 0;
        while (j < 16 and i + j < bytes.len) : (j += 1) {
            const c = bytes[i + j];
            if (c >= 32 and c < 127) {
                try buffer_writer.print("{c}", .{c});
            } else {
                try buffer_writer.print(".", .{});
            }
        }

        try buffer_writer.print("\n", .{});
    }
    try buf_out.flush();
}

// === TESTING ===

const testing = @import("../testing/testing.zig");

test "dump prints correct hex and ASCII" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "Hello, Zig!\n";
    var output_buf = std.ArrayList(u8).init(allocator);
    defer output_buf.deinit();

    try dump(input, output_buf.writer().any(), std.io.null_writer.any());

    const expected =
        \\00000000: 48 65 6c 6c 6f 2c 20 5a 69 67 21 0a              Hello, Zig!.
        \\
    ;

    try testing.expectEqualStrings(expected, output_buf.items);
}
