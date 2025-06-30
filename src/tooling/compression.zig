const std = @import("std");

const dsa = @import("dsa");

const Heap = dsa.PriorityQueue(*Node, Node.less);

const Node = struct {
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

fn frequencies(allocator: std.mem.Allocator, bytes: []const u8) !std.AutoHashMap(u8, usize) {
    var freqs = std.AutoHashMap(u8, usize).init(allocator);
    for (bytes) |byte| {
        if (freqs.contains(byte)) {
            const curr = freqs.get(byte).?;
            try freqs.put(byte, curr + 1);
        } else {
            try freqs.put(byte, 1);
        }
    }

    return freqs;
}

fn encode(heap: *Heap) !void {
    while (heap.size() > 1) {
        const left = try heap.poll();
        const right = try heap.poll();

        const internal = try Node.init(
            heap.allocator,
            0,
            left.?.freq + right.?.freq,
            left,
            right,
        );
        try heap.insert(internal);
    }
}

fn buildTable(allocator: std.mem.Allocator, node: *Node, prefix: []const u8, table: *std.AutoHashMap(u8, []const u8)) !void {
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

fn toBinaryString(encoded: std.ArrayList(u8), writer_err: std.io.AnyWriter) ![]const u8 {
    if (@rem(encoded.items.len, 8) != 0) {
        try writer_err.print("Could not convert to bytes: encoded length of {d} is not divisible by 8\n", .{encoded.items.len});
        return error.MalformedBytes;
    }

    var result = std.ArrayList(u8).init(encoded.allocator);
    defer result.deinit();

    for (encoded.items, 0..) |byte, i| {
        try result.append(byte);
        if (i != 0 and @rem(i, 8) == 0 and i != encoded.items.len - 1) {
            try result.append(' ');
        }
    }

    return try result.toOwnedSlice();
}

fn toEncodedBytes(encoded: std.ArrayList(u8), writer_err: std.io.AnyWriter) ![]const u8 {
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

pub fn compress(allocator: std.mem.Allocator, file_contents: []const u8, writer_out: std.io.AnyWriter, writer_err: std.io.AnyWriter) !void {
    if (file_contents.len == 0) {
        try writer_err.print("Compression Error: File Empty!\n", .{});
        return error.EmptyFile;
    }

    var freqs = try frequencies(allocator, file_contents);
    defer freqs.deinit();

    try writer_out.writeInt(u16, @intCast(freqs.count()), .big);
    var itr = freqs.iterator();
    while (itr.next()) |entry| {
        try writer_out.writeByte(entry.key_ptr.*);
        try writer_out.writeInt(u32, @intCast(entry.value_ptr.*), .big);
    }

    var heap = try Heap.init(allocator, .min_at_top, file_contents.len);
    itr = freqs.iterator();
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
    const root = try heap.poll();

    if (root) |tree_root| {
        var table = std.AutoHashMap(u8, []const u8).init(allocator);
        var encoded = std.ArrayList(u8).init(allocator);
        defer {
            table.deinit();
            encoded.deinit();
            tree_root.deinit();
            allocator.destroy(tree_root);
        }

        try buildTable(allocator, tree_root, &[_]u8{}, &table);

        for (file_contents) |b| {
            const code = table.get(b) orelse return error.MissingCode;
            try encoded.appendSlice(code);
        }
        const bytes = try toEncodedBytes(encoded, writer_err);
        try writer_out.writeAll(bytes);
    } else {
        try writer_err.print("Malformed frequency table!\n", .{});
        return error.MalformedFreqs;
    }
}
