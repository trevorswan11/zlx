const std = @import("std");
const token = @import("lexer/token.zig");
const tokenizer = @import("lexer/tokenizer.zig");

pub fn main() !void {
    const t0 = std.time.nanoTimestamp();
    const example00 = try std.fs.cwd().openFile("examples/test.lang", .{});
    defer example00.close();

    var buf_reader = std.io.bufferedReader(example00.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const tokens = try tokenizer.tokenize(line);
        defer tokens.deinit();

        for (tokens.items) |tok| {
            try @constCast(&tok).debug();
        }
    }
    const t1 = std.time.nanoTimestamp();
    std.debug.print("Parsing took: {d} ms", .{@as(f128, @floatFromInt(t1 - t0)) / 1_000_000.0});
}
