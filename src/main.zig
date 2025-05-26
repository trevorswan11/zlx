const std = @import("std");
const token = @import("lexer/token.zig");
const tokenizer = @import("lexer/tokenizer.zig");

pub fn main() !void {
    const example00 = try std.fs.cwd().openFile("examples/00.lang", .{});
    defer example00.close();

    var buf_reader = std.io.bufferedReader(example00.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const tokens = try tokenizer.tokenize(line);

        for (tokens.items) |tok| {
            try tok.debug();
        } 
    }
}
