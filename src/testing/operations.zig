const std = @import("std");

const testing = @import("testing.zig");

// Tests basic binary expression
test "binary_one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.driver.setWriters(writer);

    const source = "println(45.2 + 5 * 4);";

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\65.2
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests a more complex binary expression
test "binary_two" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.driver.setWriters(writer);

    const source = "println(10 * -2 + (2.4 - -2));";

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\-15.6
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests binary expressions with grouping and negative numbers
test "binary_three" {
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
        \\println(-5 + 3);    // Expect: -2
        \\println(-(3 + 1));  // Expect: -4
        \\println(-5 + -3 * 2); // Expect: -5 + (-6) = -11
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\-2
        \\-4
        \\-11
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests binary expressions with complex operators and nested expressions
test "binary_four" {
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
        \\println(3 + 4 * 5);            // Expect 23
        \\println((3 + 4) * 5);          // Expect 35
        \\println(100 / 2 - 30 + 10);    // Expect 30
        \\println(10 + 5 * 2 - 8 / 4);   // Expect 18
        \\println(2 * (3 + 5) / (1 + 1)); // Expect 8.0
        \\
        \\println("Hello, " + "world!");               // "Hello, world!"
        \\println("Answer: " + (2 + 2));               // "Answer: 4"
        \\println("Nested: " + ("Level " + (1 + 2)));  // "Nested: Level 3"
        \\
        \\println(1 + 2 * 3 + 4 * 5 + 6);          // 1 + 6 + 20 + 6 = 33
        \\println(((1 + 2) * (3 + 4)) / 5);        // ((3) * (7)) / 5 = 21 / 5 = 4.2
        \\println((100 - (50 / 2)) * (3 + 1));     // (100 - 25) * 4 = 75 * 4 = 300
        \\
        \\println(3 < 4 + 2);           // true (3 < 6)
        \\println((10 - 5) > (1 + 1));  // true (5 > 2)
        \\println((10 - 5) < (1 + 1));  // true (5 > 2)
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\23
        \\35
        \\30
        \\18
        \\8
        \\Hello, world!
        \\Answer: 4
        \\Nested: Level 3
        \\33
        \\4.2
        \\300
        \\true
        \\true
        \\false
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests some common prefix operators
test "prefix" {
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
        \\let a = 5;
        \\let b = --a;
        \\println("minus minus:");
        \\println(b);
        \\let c = ++a;
        \\println("plus plus:");
        \\println(c);
        \\println("a");
        \\println(a);
        \\
        \\println("nested:");
        \\println(++a);
        \\
        \\println("Not true: " + !true);
        \\println("Not false: " + !false);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\minus minus:
        \\4
        \\plus plus:
        \\5
        \\a
        \\5
        \\nested:
        \\6
        \\Not true: false
        \\Not false: true
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests some common postfix operators
test "postfix" {
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
        \\let a = 5;
        \\let b = a--;
        \\println("a = " + a);
        \\println("b = " + b);
        \\let c = a++;
        \\println("a = " + a);
        \\println("c = " + c);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\a = 4
        \\b = 5
        \\a = 5
        \\c = 4
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests compound assignment expression handling
test "compound_assign" {
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
        \\let x = 10;
        \\x += 5;
        \\println(x); // 15
        \\
        \\x -= 2;
        \\println(x); // 13
        \\
        \\x *= 2;
        \\println(x); // 26
        \\
        \\x /= 2;
        \\println(x); // 13
        \\
        \\x %= 4;
        \\println(x); // 1
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\15
        \\13
        \\26
        \\13
        \\1
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
