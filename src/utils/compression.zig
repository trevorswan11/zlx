const std = @import("std");

pub const COMPRESSION_HEADER: []const u8 = "ZCX";
pub const ARCHIVE_HEADER: []const u8 = "ZAX";

// === COMPRESSION ===

pub fn compress(
    file: *std.fs.File,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) anyerror!void {
    var buf_out = std.io.bufferedWriter(writer_out);
    const buffer_writer = buf_out.writer();
    try buffer_writer.writeAll(COMPRESSION_HEADER);

    std.compress.flate.compress(file.reader(), buffer_writer, .{}) catch |err| {
        try writer_err.print("Fatal error encountered while compressing: {!}\n", .{err});
        return err;
    };
    try buf_out.flush();
}

pub fn compressArchive(
    allocator: std.mem.Allocator,
    base_dir: std.fs.Dir,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) !void {
    var walker = try base_dir.walk(allocator);
    defer walker.deinit();

    try writer_out.writeAll(ARCHIVE_HEADER);
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        var compression_arena = std.heap.ArenaAllocator.init(allocator);
        defer compression_arena.deinit();
        const compression_allocator = compression_arena.allocator();

        var file = try base_dir.openFile(entry.path, .{});
        defer file.close();

        const stat = try file.stat();
        const uncompressed_size = stat.size;

        try writer_out.writeInt(u16, @intCast(entry.path.len), .big);
        try writer_out.writeAll(entry.path);
        try writer_out.writeInt(u64, uncompressed_size, .big);

        var buffer = std.ArrayList(u8).init(compression_allocator);
        defer buffer.deinit();

        try compress(&file, buffer.writer().any(), writer_err);
        try writer_out.writeInt(u64, buffer.items.len, .big);
        try writer_out.writeAll(buffer.items);
    }
}

// === DECOMPRESSION ===

pub fn decompress(
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

    std.compress.flate.decompress(reader, writer_out) catch |err| {
        try writer_err.print("Fatal error encountered while decompressing: {!}\n", .{err});
        return err;
    };
}

pub fn decompressArchive(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    out_dir: std.fs.Dir,
    writer_err: std.io.AnyWriter,
) !void {
    var magic: [3]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &magic, ARCHIVE_HEADER)) {
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

        try decompress(limited.reader().any(), file.writer().any(), writer_err);
    }
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

    try compress(&file_path, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var decompression_reader = std.io.fixedBufferStream(compressed.items);
    try decompress(decompression_reader.reader().any(), decompressed.writer().any(), std.io.null_writer.any());

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

    const result = decompress(stream.reader().any(), decompressed.writer().any(), std.io.null_writer.any());
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

    try compress(&file_path, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var decompression_reader = std.io.fixedBufferStream(compressed.items);
    try decompress(decompression_reader.reader().any(), decompressed.writer().any(), std.io.null_writer.any());

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

    try compress(&file_path, compressed.writer().any(), std.io.null_writer.any());

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var decompression_reader = std.io.fixedBufferStream(compressed.items);
    try decompress(decompression_reader.reader().any(), decompressed.writer().any(), std.io.null_writer.any());

    try testing.expectEqualSlices(u8, input, decompressed.items);
}

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
