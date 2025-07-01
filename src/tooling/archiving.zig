const std = @import("std");

const huffman = @import("huffman.zig");
const compression = @import("compression.zig");
const driver = @import("../utils/driver.zig");

const Heap = huffman.Heap;
const HuffmanNode = huffman.HuffmanNode;
const BitBuffer = huffman.BitBuffer;

pub fn compressArchive(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) !void {
    _ = allocator;
    _ = dir_path;
    _ = writer_out;
    _ = writer_err;
}

pub fn decompressArchive(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    base_out_dir: []const u8,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) !void {
    _ = allocator;
    _ = reader;
    _ = base_out_dir;
    _ = writer_out;
    _ = writer_err;
}

// === TESTING ===

const testing = @import("../testing/testing.zig");
