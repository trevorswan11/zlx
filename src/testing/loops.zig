const std = @import("std");

const testing = @import("testing.zig");

// Tests a basic foreach loop
test "foreach" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.driver.setWriters(writer);

    const source =
        \\let nums = [1, 2, 3];
        \\foreach val in nums {
        \\println(val);
        \\}
        \\
        \\foreach val, i in nums {
        \\println("" + (val + 1) + " @ index " + i);
        \\}
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\1
        \\2
        \\3
        \\2 @ index 0
        \\3 @ index 1
        \\4 @ index 2
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests a basic while loop
test "while" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.driver.setWriters(writer);

    const source =
        \\let i = 0;
        \\while i < 3 {
        \\println(i);
        \\i = i + 1;
        \\}
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\0
        \\1
        \\2
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests break statements in a loop
test "break" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.driver.setWriters(writer);

    const source =
        \\let i = 0;
        \\while i < 100 {
        \\    println(i);
        \\    i = i + 1;
        \\    if (i == 3) {
        \\        break;
        \\    }
        \\}
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\0
        \\1
        \\2
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests continue statements in a loop
test "continue" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.driver.setWriters(writer);

    const source =
        \\let i = 0;
        \\while i < 6 {
        \\if i == 3 {
        \\i = i + 1;
        \\continue;
        \\}
        \\println(i);
        \\i = i + 1;
        \\}
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\0
        \\1
        \\2
        \\4
        \\5
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
