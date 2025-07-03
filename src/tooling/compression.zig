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
    file: *std.fs.File,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) anyerror!u64 {
    var counting_writer = std.io.countingWriter(writer_out);
    var buf_out = std.io.bufferedWriter(counting_writer.writer().any());
    const buffer_writer = buf_out.writer();
    try buffer_writer.writeAll(COMPRESSION_HEADER);

    const stat = try file.stat();
    if (stat.size == 0) {
        try buffer_writer.writeInt(u16, 0, .big);
        try buffer_writer.writeByte(0);
        try buf_out.flush();
        return counting_writer.bytes_written;
    }

    // First pass, gather and write the frequencies
    var freqs = try huffman.frequenciesFromReader(allocator, file.reader().any());
    defer freqs.deinit();

    try buffer_writer.writeInt(u16, @intCast(freqs.count()), .big);
    const entries = try huffman.sortedFrequencyEntries(allocator, freqs);
    defer allocator.free(entries);

    for (entries) |entry| {
        try buffer_writer.writeByte(entry.byte);
        try buffer_writer.writeInt(u32, @intCast(entry.freq), .big);
    }

    var heap = try Heap.init(allocator, .min_at_top, entries.len);
    defer heap.deinit();
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

        // Rewind for encoding pass and encode the data
        try file.seekTo(0);
        const reader = file.reader();
        try huffman.streamEncodeFromReader(reader.any(), &table, &bit_buffer);
        const result = try bit_buffer.finishAndSlice();
        try buffer_writer.writeByte(result.pad_bits);
        try buffer_writer.writeAll(result.slice);
    } else {
        try writer_err.print("Malformed frequency table!\n", .{});
        return error.MalformedFreqs;
    }
    try buf_out.flush();
    return counting_writer.bytes_written;
}

pub fn decompress(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) anyerror!void {
    var magic: [3]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &magic, COMPRESSION_HEADER)) {
        try writer_err.print("Invalid file header\n", .{});
        return error.InvalidFileFormat;
    }

    const entries = try huffman.readFrequencyTableSorted(allocator, reader);
    defer allocator.free(entries);

    if (entries.len == 0) {
        // Still need to read the padding byte for completeness
        _ = try reader.readByte();
        return;
    }

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

    var tmp_dir = std.testing.tmpDir(.{
        .iterate = true,
    });
    defer tmp_dir.cleanup();

    errdefer {
        const path: []const u8 = &tmp_dir.sub_path;
        var exists = true;
        std.fs.cwd().access(path, .{}) catch {
            exists = false;
        };
        if (exists) {
            std.fs.cwd().deleteTree(path) catch {};
        }
    }

    var file_path = try tmp_dir.dir.createFile("input.txt", .{
        .read = true,
    });
    defer file_path.close();
    try file_path.writeAll(input);
    try file_path.seekTo(0);

    var compressed = std.ArrayList(u8).init(allocator);
    defer compressed.deinit();

    _ = try compress(allocator, &file_path, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var decompression_reader = std.io.fixedBufferStream(compressed.items);
    try decompress(allocator, decompression_reader.reader().any(), decompressed.writer().any(), std.io.null_writer.any());

    try testing.expectEqualSlices(u8, input, decompressed.items);
}

test "decompress fails with invalid magic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const fake = "BAD";
    var stream = std.io.fixedBufferStream(fake);
    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    const result = decompress(allocator, stream.reader().any(), decompressed.writer().any(), std.io.null_writer.any());
    try testing.expectError(error.InvalidFileFormat, result);
}

test "compress and decompress empty file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input: []const u8 = "";

    var tmp_dir = std.testing.tmpDir(.{
        .iterate = true,
    });
    defer tmp_dir.cleanup();

    errdefer {
        const path: []const u8 = &tmp_dir.sub_path;
        var exists = true;
        std.fs.cwd().access(path, .{}) catch {
            exists = false;
        };
        if (exists) {
            std.fs.cwd().deleteTree(path) catch {};
        }
    }

    var file_path = try tmp_dir.dir.createFile("input.txt", .{
        .read = true,
    });
    defer file_path.close();
    try file_path.writeAll(input);
    try file_path.seekTo(0);

    var compressed = std.ArrayList(u8).init(allocator);
    defer compressed.deinit();

    _ = try compress(allocator, &file_path, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var decompression_reader = std.io.fixedBufferStream(compressed.items);
    try decompress(allocator, decompression_reader.reader().any(), decompressed.writer().any(), std.io.null_writer.any());

    try testing.expectEqualSlices(u8, input, decompressed.items);
}

test "compress and decompress repeated characters - special case" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "aaaaaa";

    var tmp_dir = std.testing.tmpDir(.{
        .iterate = true,
    });
    defer tmp_dir.cleanup();

    errdefer {
        const path: []const u8 = &tmp_dir.sub_path;
        var exists = true;
        std.fs.cwd().access(path, .{}) catch {
            exists = false;
        };
        if (exists) {
            std.fs.cwd().deleteTree(path) catch {};
        }
    }

    var file_path = try tmp_dir.dir.createFile("input.txt", .{
        .read = true,
    });
    defer file_path.close();
    try file_path.writeAll(input);
    try file_path.seekTo(0);

    var compressed = std.ArrayList(u8).init(allocator);
    defer compressed.deinit();

    _ = try compress(allocator, &file_path, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var decompression_reader = std.io.fixedBufferStream(compressed.items);
    try decompress(allocator, decompression_reader.reader().any(), decompressed.writer().any(), std.io.null_writer.any());

    try testing.expectEqualSlices(u8, input, decompressed.items);
}
