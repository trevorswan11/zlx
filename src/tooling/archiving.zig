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
    try writer_out.writeAll(compression.ARCHIVE_HEADER);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    try recurseDir(
        allocator,
        dir,
        dir_path,
        "",
        writer_out,
        writer_err,
    );
}

fn recurseDir(
    allocator: std.mem.Allocator,
    base_dir: std.fs.Dir,
    base_path: []const u8,
    rel_path: []const u8,
    writer_out: std.io.AnyWriter,
    writer_err: std.io.AnyWriter,
) !void {
    var walker = try base_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const new_rel_path = try std.fs.path.join(allocator, &[_][]const u8{ rel_path, entry.basename });
        defer allocator.free(new_rel_path);

        if (entry.kind == .directory) {
            var subdir = try base_dir.openDir(entry.path, .{ .iterate = true });
            defer subdir.close();

            try recurseDir(
                allocator,
                subdir,
                base_path,
                new_rel_path,
                writer_out,
                writer_err,
            );
        } else if (entry.kind == .file) {
            const file = try base_dir.openFile(entry.path, .{});
            defer file.close();

            const stat = try file.stat();
            const uncompressed_size = stat.size;

            const contents = try allocator.alloc(u8, uncompressed_size);
            defer allocator.free(contents);
            _ = try file.readAll(contents);

            // `entry.path` is the relative path, good for archive
            try writer_out.writeInt(u16, @intCast(entry.path.len), .big);
            try writer_out.writeAll(entry.path);
            try writer_out.writeInt(u64, uncompressed_size, .big);

            try compression.compress(allocator, contents, writer_out, writer_err);
        }
    }
}

pub fn decompressArchive(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    base_out_dir: []const u8,
    writer_err: std.io.AnyWriter,
) !void {
    while (true) {
        // Try reading path length
        const path_len = reader.readInt(u16, .big) catch |err| switch (err) {
            error.EndOfStream => break, // finished
            else => return err,
        };

        const path_buf = try allocator.alloc(u8, path_len);
        try reader.readNoEof(path_buf);

        // const uncompressed_size = try reader.readInt(u64, .big);

        // Build the full output file path
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ base_out_dir, path_buf });

        // Ensure the parent directories exist
        const parent = std.fs.path.dirname(full_path) orelse ".";
        const Wtf8View = std.unicode.Wtf8View;
        _ = Wtf8View.init(parent) catch {
            try writer_err.print("Invalid WTF-8 path skipped: {s}\n", .{parent});
            continue;
        };
        try std.fs.cwd().makePath(parent);

        // Create output file
        _ = Wtf8View.init(full_path) catch {
            continue;
        };
        const output_file = try std.fs.cwd().createFile(full_path, .{ .truncate = true });
        defer output_file.close();
        const file_writer = output_file.writer().any();
        try compression.decompress(allocator, reader, base_out_dir, file_writer, writer_err);
    }
}

// === TESTING ===

const testing = @import("../testing/testing.zig");
