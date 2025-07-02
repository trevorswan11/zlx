const std = @import("std");

const huffman = @import("huffman.zig");
const compression = @import("compression.zig");
const driver = @import("../utils/driver.zig");

const Heap = huffman.Heap;
const HuffmanNode = huffman.HuffmanNode;
const BitBuffer = huffman.BitBuffer;

pub fn compressArchive(
    allocator: std.mem.Allocator,
    base_dir: std.fs.Dir,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) !void {
    var walker = try base_dir.walk(allocator);
    defer walker.deinit();

    try writer_out.writeAll(compression.ARCHIVE_HEADER);
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        var compression_arena = std.heap.ArenaAllocator.init(allocator);
        defer compression_arena.deinit();
        const compression_allocator = compression_arena.allocator();

        const file = try base_dir.openFile(entry.path, .{});
        defer file.close();

        const stat = try file.stat();
        const uncompressed_size = stat.size;

        const contents = try compression_allocator.alloc(u8, uncompressed_size);
        defer compression_allocator.free(contents);
        _ = try file.readAll(contents);

        try writer_out.writeInt(u16, @intCast(entry.path.len), .big);
        try writer_out.writeAll(entry.path);
        try writer_out.writeInt(u64, uncompressed_size, .big);

        var buffer = std.ArrayList(u8).init(compression_allocator);
        defer buffer.deinit();

        try compression.compress(compression_allocator, contents, buffer.writer().any(), writer_err);
        try writer_out.writeInt(u64, buffer.items.len, .big);
        try writer_out.writeAll(buffer.items);
    }
}

pub fn decompressArchive(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    out_dir: std.fs.Dir,
    writer_err: std.io.AnyWriter,
) !void {
    var magic: [3]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &magic, compression.ARCHIVE_HEADER)) {
        try writer_err.print("Invalid file header\n", .{});
        return error.InvalidFileFormat;
    }

    while (true) {
        const path_len = reader.readInt(u16, .big) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        var decompression_arena = std.heap.ArenaAllocator.init(allocator);
        defer decompression_arena.deinit();
        const decompression_allocator = decompression_arena.allocator();

        const path_buf = try decompression_allocator.alloc(u8, path_len);
        defer decompression_allocator.free(path_buf);

        try reader.readNoEof(path_buf);
        _ = try reader.readInt(u64, .big);
        const compressed_size = try reader.readInt(u64, .big);
        var limited = std.io.limitedReader(reader, compressed_size);
        const parent = std.fs.path.dirname(path_buf) orelse ".";
        try out_dir.makePath(parent);
        var file = try out_dir.createFile(path_buf, .{ .truncate = true });
        defer file.close();

        try compression.decompress(decompression_allocator, limited.reader().any(), file.writer().any(), writer_err);
    }
}

// === TESTING ===

const testing = @import("../testing/testing.zig");

test "compress and decompress archive round-trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

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

    var base = try tmp_dir.dir.makeOpenPath("source", .{
        .iterate = true,
    });
    defer base.close();

    _ = try base.makePath("a/b");
    const file1 = try base.createFile("a/hello.txt", .{});
    try file1.writeAll("hello world");
    file1.close();

    const file2 = try base.createFile("a/b/data.txt", .{});
    try file2.writeAll("zig is awesome");
    file2.close();

    // Write compressed archive to memory
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try compressArchive(allocator, base, buffer.writer().any(), std.io.null_writer.any());

    // Create output directory
    var out = try tmp_dir.dir.makeOpenPath("output", .{});
    defer out.close();

    var stream = std.io.fixedBufferStream(buffer.items);
    try decompressArchive(allocator, stream.reader().any(), out, std.io.null_writer.any());

    // === Validate files ===

    // Read output a/hello.txt
    {
        var f = try out.openFile("a/hello.txt", .{});
        defer f.close();
        const contents = try f.readToEndAlloc(allocator, 100);
        defer allocator.free(contents);
        try testing.expectEqualStrings("hello world", contents);
    }

    // Read output a/b/data.txt
    {
        var f = try out.openFile("a/b/data.txt", .{});
        defer f.close();
        const contents = try f.readToEndAlloc(allocator, 100);
        defer allocator.free(contents);
        try testing.expectEqualStrings("zig is awesome", contents);
    }
}

test "compress and decompress archive round-trip (with empty file)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
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

    var base = try tmp_dir.dir.makeOpenPath("source", .{ .iterate = true });
    defer base.close();

    _ = try base.makePath("a/b");

    // non-empty file
    const file1 = try base.createFile("a/hello.txt", .{});
    try file1.writeAll("hello world");
    file1.close();

    // empty file
    const file2 = try base.createFile("a/b/empty.txt", .{});
    file2.close();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try compressArchive(allocator, base, buffer.writer().any(), std.io.null_writer.any());

    var out = try tmp_dir.dir.makeOpenPath("output", .{});
    defer out.close();

    var stream = std.io.fixedBufferStream(buffer.items);
    try decompressArchive(allocator, stream.reader().any(), out, std.io.null_writer.any());

    // === Verify non-empty file ===
    {
        var f = try out.openFile("a/hello.txt", .{});
        defer f.close();
        const contents = try f.readToEndAlloc(allocator, 100);
        defer allocator.free(contents);
        try testing.expectEqualStrings("hello world", contents);
    }

    // === Verify empty file ===
    {
        var f = try out.openFile("a/b/empty.txt", .{});
        defer f.close();
        const contents = try f.readToEndAlloc(allocator, 100);
        defer allocator.free(contents);
        try testing.expectEqualSlices(u8, "", contents);
    }
}
