const std = @import("std");
const dsa = @import("dsa");

// Min-Heap Node Data Structure
pub const Heap = dsa.PriorityQueue(*Node, Node.less);
pub const Node = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: u8,
    freq: usize,
    left: ?*Node = null,
    right: ?*Node = null,

    pub fn init(allocator: std.mem.Allocator, data: u8, freq: usize, left: ?*Node, right: ?*Node) !*Self {
        const node = try allocator.create(Node);
        node.* = Self{
            .allocator = allocator,
            .data = data,
            .freq = freq,
            .left = left,
            .right = right,
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        if (self.left) |left| {
            left.deinit();
            self.allocator.destroy(left);
        }
        if (self.right) |right| {
            right.deinit();
            self.allocator.destroy(right);
        }
    }

    pub fn less(a: *Node, b: *Node) bool {
        return a.freq < b.freq;
    }
};

// === COMPRESSION ===

pub fn frequencies(allocator: std.mem.Allocator, bytes: []const u8) !std.AutoHashMap(u8, usize) {
    var freqs = std.AutoHashMap(u8, usize).init(allocator);
    for (bytes) |byte| {
        if (freqs.contains(byte)) {
            if (freqs.get(byte)) |curr| {
                try freqs.put(byte, curr + 1);
            }
        } else {
            try freqs.put(byte, 1);
        }
    }

    return freqs;
}

pub fn encode(heap: *Heap) !void {
    while (heap.size() > 1) {
        const left: *Node = if (try heap.poll()) |l| blk: {
            break :blk l;
        } else {
            return error.MalformedHuffmanTree;
        };
        const right: *Node = if (try heap.poll()) |r| blk: {
            break :blk r;
        } else {
            return error.MalformedHuffmanTree;
        };

        const internal = try Node.init(
            heap.allocator,
            0,
            left.freq + right.freq,
            left,
            right,
        );
        try heap.insert(internal);
    }
}

pub fn buildTable(allocator: std.mem.Allocator, node: *Node, prefix: []const u8, table: *std.AutoHashMap(u8, []const u8)) !void {
    if (node.left == null and node.right == null) {
        const code = try allocator.dupe(u8, prefix);
        try table.put(node.data, code);
        return;
    }

    var next = try allocator.alloc(u8, prefix.len + 1);
    std.mem.copyForwards(u8, next[0..prefix.len], prefix);
    if (node.left) |left| {
        next[prefix.len] = '0';
        try buildTable(allocator, left, next, table);
    }

    if (node.right) |right| {
        next[prefix.len] = '1';
        try buildTable(allocator, right, next, table);
    }
}

pub fn padToByteAlignment(encoded: *std.ArrayList(u8)) !usize {
    const extra = @rem(encoded.items.len, 8);
    if (extra == 0) {
        return 0;
    }

    const pad_bits = 8 - extra;
    for (0..pad_bits) |_| {
        try encoded.append('0');
    }
    return pad_bits;
}

pub fn toEncodedBytes(encoded: std.ArrayList(u8), writer_err: std.io.AnyWriter) ![]const u8 {
    if (@rem(encoded.items.len, 8) != 0) {
        try writer_err.print("Could not convert to bytes: encoded length of {d} is not divisible by 8\n", .{encoded.items.len});
        return error.MalformedBytes;
    }

    const num_bytes = @divExact(encoded.items.len, 8);
    var result = try std.ArrayList(u8).initCapacity(encoded.allocator, num_bytes);
    defer result.deinit();

    var i: usize = 0;
    while (i < encoded.items.len) : (i += 8) {
        var byte: u8 = 0;
        for (0..8) |bit_index| {
            if (encoded.items[i + bit_index] == '1') {
                byte |= @as(u8, 1) << @intCast(7 - bit_index);
            }
        }
        try result.append(byte);
    }

    return try result.toOwnedSlice();
}

// === DECOMPRESSION ===

pub fn readFrequencyTable(allocator: std.mem.Allocator, reader: std.io.AnyReader) !std.AutoHashMap(u8, usize) {
    var freqs = std.AutoHashMap(u8, usize).init(allocator);

    const count = try reader.readInt(u16, .big);
    for (0..count) |_| {
        const symbol = try reader.readByte();
        const freq = try reader.readInt(u32, .big);
        try freqs.put(symbol, freq);
    }

    return freqs;
}

pub fn buildTreeFromFrequencies(allocator: std.mem.Allocator, freqs: std.AutoHashMap(u8, usize)) !*Node {
    var heap = try Heap.init(allocator, .min_at_top, freqs.count());
    var itr = freqs.iterator();
    while (itr.next()) |entry| {
        const node = try Node.init(
            allocator,
            entry.key_ptr.*,
            entry.value_ptr.*,
            null,
            null,
        );
        try heap.insert(node);
    }
    try encode(&heap);
    return try heap.poll() orelse error.MalformedHuffmanTree;
}

// === TESTING ===

const testing = @import("../testing/testing.zig");

test "frequencies correctly counts bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "aabcccaaa";
    const expected = [_]struct { u8, usize }{
        .{ 'a', 5 },
        .{ 'b', 1 },
        .{ 'c', 3 },
    };

    var freqs = try frequencies(allocator, input);
    defer freqs.deinit();

    for (expected) |pair| {
        const actual = freqs.get(pair.@"0") orelse return error.MissingKey;
        try testing.expectEqual(pair.@"1", actual);
    }
}

test "encode and buildTreeFromFrequencies returns valid root" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "abacabad";
    var freqs = try frequencies(allocator, input);
    defer freqs.deinit();

    const root = try buildTreeFromFrequencies(allocator, freqs);
    defer {
        root.deinit();
        allocator.destroy(root);
    }

    try testing.expect(root.freq == input.len);
}

test "buildTable generates prefix codes for all leaves" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const input = "abcabcababc";
    var freqs = try frequencies(allocator, input);
    defer freqs.deinit();

    const root = try buildTreeFromFrequencies(allocator, freqs);
    defer {
        root.deinit();
        allocator.destroy(root);
    }

    var table = std.AutoHashMap(u8, []const u8).init(allocator);
    defer {
        var it = table.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        table.deinit();
    }

    try buildTable(allocator, root, &[_]u8{}, &table);

    var found = std.AutoHashMap(u8, bool).init(allocator);
    defer found.deinit();

    for (input) |ch| {
        if (!found.contains(ch)) {
            _ = try found.put(ch, true);
            const code = table.get(ch) orelse return error.MissingCode;
            try testing.expect(code.len > 0);
        }
    }
}

test "padToByteAlignment adds correct number of bits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var encoded = std.ArrayList(u8).init(allocator);
    defer encoded.deinit();

    try encoded.appendSlice("1010101"); // 7 bits
    const pad = try padToByteAlignment(&encoded);
    try testing.expectEqual(@as(usize, 1), pad);
    try testing.expectEqual(encoded.items.len, 8);
    try testing.expectEqual(encoded.items[7], '0');
}

test "toEncodedBytes packs bits into bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var encoded = std.ArrayList(u8).init(allocator);
    defer encoded.deinit();

    try encoded.appendSlice("01000001"); // = 0x41
    const bytes = try toEncodedBytes(encoded, std.io.null_writer.any());
    try testing.expectEqualSlices(u8, &[1]u8{0x41}, bytes);
}

test "readFrequencyTable reads known map from buffer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    // count = 2
    try buffer.appendSlice(&[_]u8{
        0x00, 0x02, // u16 count = 2
        'x', 0x00, 0x00, 0x00, 0x05, // 'x': 5
        'y', 0x00, 0x00, 0x00, 0x03, // 'y': 3
    });

    var stream = std.io.fixedBufferStream(buffer.items);
    var map = try readFrequencyTable(allocator, stream.reader().any());
    defer map.deinit();

    try testing.expectEqual(@as(usize, 5), map.get('x') orelse return error.MissingKey);
    try testing.expectEqual(@as(usize, 3), map.get('y') orelse return error.MissingKey);
}

test "buildTreeFromFrequencies returns proper root node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var freqs = std.AutoHashMap(u8, usize).init(allocator);
    defer freqs.deinit();

    try freqs.put('a', 4);
    try freqs.put('b', 2);
    try freqs.put('c', 1);

    const root = try buildTreeFromFrequencies(allocator, freqs);
    defer {
        root.deinit();
        allocator.destroy(root);
    }

    try testing.expectEqual(@as(usize, 7), root.freq);
}
