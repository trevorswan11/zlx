const std = @import("std");

pub fn hexDump(bytes: []const u8, writer_out: std.io.AnyWriter, writer_err: std.io.AnyWriter) !void {
    if (bytes.len == 0) {
        try writer_err.print("File Empty!\n", .{});
        return error.EmptyFile;
    }

    // Get buffered writer for efficient printing
    var buf_out = std.io.bufferedWriter(writer_out);
    const buffer_writer = buf_out.writer();

    var i: usize = 0;
    while (i < bytes.len) {
        // Print offset
        try buffer_writer.print("{x:0>8}: ", .{i});

        // Print hex values (16 per line)
        var j: usize = 0;
        while (j < 16) {
            if (i + j < bytes.len) {
                try buffer_writer.print("{x:0>2} ", .{bytes[i + j]});
            } else {
                try buffer_writer.print("   ", .{});
            }
            j += 1;
        }

        // Print ASCII representation
        try buffer_writer.print(" ", .{});
        j = 0;
        while (j < 16 and i + j < bytes.len) {
            const c = bytes[i + j];
            if (c >= 32 and c < 127) {
                try buffer_writer.print("{c}", .{c});
            } else {
                try buffer_writer.print(".", .{});
            }
            j += 1;
        }

        try buffer_writer.print("\n", .{});
        i += 16;
    }
    try buf_out.flush();
}
