const std = @import("std");
const dsa = @import("dsa");

const BUFFER_SIZE: usize = 65536;

// Min-Heap & Data Structures
pub const Heap = dsa.PriorityQueue(*HuffmanNode, HuffmanNode.less);
pub const HuffmanNode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: u8,
    freq: usize,
    left: ?*HuffmanNode = null,
    right: ?*HuffmanNode = null,

    pub fn init(allocator: std.mem.Allocator, data: u8, freq: usize, left: ?*HuffmanNode, right: ?*HuffmanNode) !*Self {
        const node = try allocator.create(HuffmanNode);
        node.* = Self{
            .allocator = allocator,
            .data = data,
            .freq = freq,
            .left = left,
            .right = right,
        };
        return node;
    }

    pub fn deinit(self: *HuffmanNode) void {
        if (self.left) |left| {
            left.deinit();
            self.allocator.destroy(left);
        }
        if (self.right) |right| {
            right.deinit();
            self.allocator.destroy(right);
        }
    }

    pub fn less(a: *HuffmanNode, b: *HuffmanNode) bool {
        if (a.freq < b.freq) {
            return true;
        } else if (a.freq > b.freq) {
            return false;
        }

        const a_leaf = a.left == null and a.right == null;
        const b_leaf = b.left == null and b.right == null;

        if (a_leaf and b_leaf) {
            return a.data < b.data;
        }

        // Final tie-breaker: pointer address
        return @intFromPtr(a) < @intFromPtr(b);
    }
};

pub const BitBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    list: std.ArrayList(u8),
    current_byte: u8 = 0,
    bit_index: u8 = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .list = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn appendBit(self: *Self, bit: u1) !void {
        self.current_byte |= @as(u8, bit) << @intCast(7 - self.bit_index);
        self.bit_index += 1;

        if (self.bit_index == 8) {
            try self.list.append(self.current_byte);
            self.current_byte = 0;
            self.bit_index = 0;
        }
    }

    pub fn appendBitsFromSlice(self: *Self, bits: []const u8) !void {
        for (bits) |b| {
            switch (b) {
                '0' => try self.appendBit(0),
                '1' => try self.appendBit(1),
                else => return error.InvalidBit,
            }
        }
    }

    pub fn finish(self: *Self) !usize {
        if (self.bit_index > 0) {
            try self.list.append(self.current_byte);
            return 8 - @as(u8, @intCast(self.bit_index));
        }
        return 0;
    }

    pub fn finishAndSlice(self: *Self) !struct {
        pad_bits: u8,
        slice: []u8,
    } {
        const pad = if (self.bit_index > 0) blk: {
            const used: u8 = @intCast(self.bit_index);
            try self.list.append(self.current_byte);
            break :blk 8 - used;
        } else 0;

        return .{
            .pad_bits = pad,
            .slice = try self.list.toOwnedSlice(),
        };
    }

    pub fn toOwnedSlice(self: *Self) ![]u8 {
        return try self.list.toOwnedSlice();
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit();
    }
};

const TableEntry = struct { byte: u8, freq: usize };

pub fn sortedFrequencyEntries(
    allocator: std.mem.Allocator,
    freqs: std.AutoHashMap(u8, usize),
) ![]TableEntry {
    var entries = try allocator.alloc(TableEntry, freqs.count());

    var i: usize = 0;
    var itr = freqs.iterator();
    while (itr.next()) |entry| {
        entries[i] = .{
            .byte = entry.key_ptr.*,
            .freq = entry.value_ptr.*,
        };
        i += 1;
    }

    std.sort.insertion(
        TableEntry,
        entries,
        {},
        struct {
            pub fn lessThan(_: void, a: TableEntry, b: TableEntry) bool {
                return a.freq < b.freq or (a.freq == b.freq and a.byte < b.byte);
            }
        }.lessThan,
    );

    return entries;
}

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

pub fn frequenciesFromReader(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
) !std.AutoHashMap(u8, usize) {
    var freqs = std.AutoHashMap(u8, usize).init(allocator);
    var buf: [BUFFER_SIZE]u8 = undefined;

    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;
        for (buf[0..n]) |b| {
            if (freqs.get(b)) |val| {
                try freqs.put(b, val + 1);
            } else {
                try freqs.put(b, 1);
            }
        }
    }
    return freqs;
}

pub fn encode(heap: *Heap) !void {
    while (heap.size() > 1) {
        const left: *HuffmanNode = if (try heap.poll()) |l| blk: {
            break :blk l;
        } else {
            return error.MalformedHuffmanTree;
        };
        const right: *HuffmanNode = if (try heap.poll()) |r| blk: {
            break :blk r;
        } else {
            return error.MalformedHuffmanTree;
        };

        const internal = try HuffmanNode.init(
            heap.allocator,
            0,
            left.freq + right.freq,
            left,
            right,
        );
        try heap.insert(internal);
    }
}

pub fn streamEncodeFromReader(
    reader: std.io.AnyReader,
    table: *const std.AutoHashMap(u8, []const u8),
    bit_buffer: *BitBuffer,
) !void {
    var buf: [BUFFER_SIZE]u8 = undefined;
    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;
        for (buf[0..n]) |b| {
            const bits = table.get(b) orelse return error.MissingHuffmanCode;
            try bit_buffer.appendBitsFromSlice(bits);
        }
    }
}

pub fn buildTable(allocator: std.mem.Allocator, node: *HuffmanNode, prefix: []const u8, table: *std.AutoHashMap(u8, []const u8)) !void {
    if (node.left == null and node.right == null) {
        const code = try allocator.dupe(u8, prefix);
        try table.put(node.data, code);
        return;
    }

    if (node.left) |left| {
        var next = try allocator.alloc(u8, prefix.len + 1);
        std.mem.copyForwards(u8, next[0..prefix.len], prefix);
        next[prefix.len] = '0';
        try buildTable(allocator, left, next, table);
        allocator.free(next);
    }

    if (node.right) |right| {
        var next = try allocator.alloc(u8, prefix.len + 1);
        std.mem.copyForwards(u8, next[0..prefix.len], prefix);
        next[prefix.len] = '1';
        try buildTable(allocator, right, next, table);
        allocator.free(next);
    }
}

// === DECOMPRESSION ===

pub fn readFrequencyTableSorted(allocator: std.mem.Allocator, reader: std.io.AnyReader) ![]TableEntry {
    const num_entries = try reader.readInt(u16, .big);
    const entries = try allocator.alloc(TableEntry, num_entries);

    for (entries) |*entry| {
        entry.byte = try reader.readByte();
        entry.freq = try reader.readInt(u32, .big);
    }

    return entries;
}

pub fn buildTreeFromFrequencySorted(allocator: std.mem.Allocator, entries: []const TableEntry) !*HuffmanNode {
    var heap = try Heap.init(allocator, .min_at_top, entries.len);
    for (entries) |entry| {
        const node = try HuffmanNode.init(
            allocator,
            entry.byte,
            entry.freq,
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

test "sortedFrequencyEntries orders by frequency then byte" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var map = std.AutoHashMap(u8, usize).init(allocator);
    defer map.deinit();

    try map.put('b', 3);
    try map.put('a', 3);
    try map.put('c', 1);

    const sorted = try sortedFrequencyEntries(allocator, map);
    defer allocator.free(sorted);

    try testing.expectEqual(@as(u8, 'c'), sorted[0].byte); // freq = 1
    try testing.expectEqual(@as(u8, 'a'), sorted[1].byte); // freq = 3, a < b
    try testing.expectEqual(@as(u8, 'b'), sorted[2].byte);
}

test "HuffmanNode.less prioritizes freq then byte then address" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const a = try HuffmanNode.init(allocator, 'a', 1, null, null);
    const b = try HuffmanNode.init(allocator, 'b', 2, null, null);
    defer {
        a.deinit();
        allocator.destroy(a);
        b.deinit();
        allocator.destroy(b);
    }

    try testing.expect(HuffmanNode.less(a, b)); // 1 < 2
    try testing.expect(!HuffmanNode.less(b, a)); // 2 > 1
}

test "buildTreeFromFrequencySorted produces correct tree for two symbols" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const entries = try allocator.alloc(TableEntry, 2);
    defer allocator.free(entries);

    entries[0] = .{ .byte = 'x', .freq = 5 };
    entries[1] = .{ .byte = 'y', .freq = 9 };

    const root = try buildTreeFromFrequencySorted(allocator, entries);
    defer {
        root.deinit();
        allocator.destroy(root);
    }

    try testing.expect(root.left != null and root.right != null);
    try testing.expectEqual(@as(usize, 14), root.freq);
    try testing.expectEqual(@as(u8, 'x'), root.left.?.data);
    try testing.expectEqual(@as(u8, 'y'), root.right.?.data);
}

test "BitBuffer packs bits and computes padding correctly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var buf = BitBuffer.init(allocator);
    defer buf.deinit();

    try buf.appendBitsFromSlice("101");
    const result = try buf.finishAndSlice();

    try testing.expectEqual(@as(u8, 5), result.pad_bits); // 3 bits used → 5 padding
    try testing.expectEqual(@as(usize, 1), result.slice.len);
    try testing.expectEqual(@as(u8, 0b1010_0000), result.slice[0]);
}
