const std = @import("std");

const huffman = @import("huffman.zig");
const archiving = @import("archiving.zig");

const Heap = huffman.Heap;
const HuffmanNode = huffman.HuffmanNode;
const BitBuffer = huffman.BitBuffer;

pub const compressArchive = archiving.compressArchive;
pub const decompressArchive = archiving.decompressArchive;

pub const COMPRESSION_HEADER: []const u8 = "ZCX";
pub const ARCHIVE_HEADER: []const u8 = "ZAX";

pub fn compress(
    allocator: std.mem.Allocator,
    file_contents: []const u8,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) anyerror!void {
    if (file_contents.len == 0) {
        try writer_err.print("Compression Error: File Empty!\n", .{});
        return error.EmptyFile;
    }

    var freqs = try huffman.frequencies(allocator, file_contents);
    defer freqs.deinit();

    var buf_out = std.io.bufferedWriter(writer_out);
    const buffer_writer = buf_out.writer();

    try buffer_writer.writeAll(COMPRESSION_HEADER);
    try buffer_writer.writeInt(u16, @intCast(freqs.count()), .big);
    const entries = try huffman.sortedFrequencyEntries(allocator, freqs);
    defer allocator.free(entries);

    for (entries) |entry| {
        try buffer_writer.writeByte(entry.byte);
        try buffer_writer.writeInt(u32, @intCast(entry.freq), .big);
    }

    var heap = try Heap.init(allocator, .min_at_top, file_contents.len);
    var itr = freqs.iterator();
    while (itr.next()) |entry| {
        const node = try HuffmanNode.init(
            allocator,
            entry.key_ptr.*,
            entry.value_ptr.*,
            null,
            null,
        );
        try heap.insert(node);
    }
    try huffman.encode(&heap);
    const root = try heap.poll();

    if (root) |tree_root| {
        var table = std.AutoHashMap(u8, []const u8).init(allocator);
        var bit_buffer = BitBuffer.init(allocator);
        defer {
            table.deinit();
            bit_buffer.deinit();
            tree_root.deinit();
            allocator.destroy(tree_root);
        }

        try huffman.buildTable(allocator, tree_root, &[_]u8{}, &table);
        for (file_contents) |b| {
            const raw_code = table.get(b) orelse return error.MissingHuffmanCode;
            try bit_buffer.appendBitsFromSlice(raw_code);
        }
        const result = try bit_buffer.finishAndSlice();
        try buffer_writer.writeByte(result.pad_bits);
        try buffer_writer.writeAll(result.slice);
    } else {
        try writer_err.print("Malformed frequency table!\n", .{});
        return error.MalformedFreqs;
    }
    try buf_out.flush();
}

pub fn decompress(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    base_out_dir: []const u8,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) anyerror!void {
    var magic: [3]u8 = undefined;
    try reader.readNoEof(&magic);
    if (std.mem.eql(u8, &magic, ARCHIVE_HEADER)) {
        return try archiving.decompressArchive(allocator, reader, base_out_dir, writer_out, writer_err);
    } else if (!std.mem.eql(u8, &magic, COMPRESSION_HEADER)) {
        try writer_err.print("Invalid file header\n", .{});
        return error.InvalidFileFormat;
    }

    const entries = try huffman.readFrequencyTableSorted(allocator, reader);
    defer allocator.free(entries);

    var buf_out = std.io.bufferedWriter(writer_out);
    const buffer_writer = buf_out.writer();

    const root = try huffman.buildTreeFromFrequencySorted(allocator, entries);
    var compressed = std.ArrayList(u8).init(allocator);
    defer {
        compressed.deinit();
        root.deinit();
        allocator.destroy(root);
    }

    var total_symbols: usize = 0;
    for (entries) |entry| {
        total_symbols += entry.freq;
    }
    
    const pad_bits = try reader.readByte();
    if (pad_bits >= 8) {
        return error.InvalidPadding;
    }

    // Special case: only one symbol in the input
    if (root.left == null and root.right == null) {
        for (0..total_symbols) |_| {
            try buffer_writer.writeByte(root.data);
        }
        try buf_out.flush();
        return;
    }

    // Read the rest of the data into memory
    while (true) {
        const byte = reader.readByte() catch break;
        try compressed.append(byte);
    }

    var decoded: usize = 0;
    var node = root;
    outer: for (compressed.items, 0..) |byte, i| {
        const is_last = (i == compressed.items.len - 1);
        const bits_in_bytes: u8 = if (is_last and pad_bits != 0) blk: {
            break :blk @intCast(8 - pad_bits);
        } else blk: {
            break :blk 8;
        };

        for (0..bits_in_bytes) |j| {
            const bit: u1 = @intCast((byte >> @intCast(7 - j)) & 1);
            node = if (bit == 0) blk: {
                break :blk node.left orelse return error.MalformedTree;
            } else blk: {
                break :blk node.right orelse return error.MalformedTree;
            };

            if (node.left == null and node.right == null) {
                try buffer_writer.writeByte(node.data);
                decoded += 1;
                node = root;

                if (decoded >= total_symbols) {
                    break :outer;
                }
            }
        }
    }
    try buf_out.flush();
}

// === TESTING ===

const testing = @import("../testing/testing.zig");

// Round-trip test

test "compress and decompress round-trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "the quick brown fox jumps over the lazy dog";

    var compressed = std.ArrayList(u8).init(allocator);
    defer compressed.deinit();

    try compress(allocator, input, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var reader = std.io.fixedBufferStream(compressed.items);
    try decompress(allocator, reader.reader().any(), "", decompressed.writer().any(), std.io.null_writer.any());

    try testing.expectEqualSlices(u8, input, decompressed.items);
}

test "compress fails on empty input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input: []const u8 = "";

    var compressed = std.ArrayList(u8).init(allocator);
    defer compressed.deinit();

    const result = compress(allocator, input, compressed.writer().any(), std.io.null_writer.any());
    try testing.expectError(error.EmptyFile, result);
}

test "decompress fails with invalid magic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const fake = "BAD";
    var stream = std.io.fixedBufferStream(fake);
    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    const result = decompress(allocator, stream.reader().any(), "", decompressed.writer().any(), std.io.null_writer.any());
    try testing.expectError(error.InvalidFileFormat, result);
}

test "compress and decompress repeated characters - special case" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "aaaaaa";

    var compressed = std.ArrayList(u8).init(allocator);
    defer compressed.deinit();

    try compress(allocator, input, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var reader = std.io.fixedBufferStream(compressed.items);
    try decompress(allocator, reader.reader().any(), "", decompressed.writer().any(), std.io.null_writer.any());

    try testing.expectEqualSlices(u8, input, decompressed.items);
}
