const std = @import("std");

const testing = @import("testing.zig");

// Tests basic function declaration and use
test "fn" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\fn add(a: int, b: int): int {
        \\const res = a + b;
        \\res;
        \\}
        \\println(add(5, 10));
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\15
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests function declarations without parameter types
test "any_param" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\fn no_type(num) {
        \\print(num);
        \\}
        \\
        \\no_type(2);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\2
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests function's ability to be bound to variables
test "bound" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\class Greeter {
        \\let name: string;
        \\
        \\fn ctor(name: string) {
        \\    this.name = name;
        \\}
        \\
        \\fn greet() {
        \\    println("Hello, " + this.name);
        \\}
        \\}
        \\
        \\let g = new Greeter("Ziggy");
        \\let greet = g.greet;
        \\greet();
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\Hello, Ziggy
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests function's ability to be passed as parameters to other functions
test "first_class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\class Greeter {
        \\let name: string;
        \\
        \\fn ctor(name: string) {
        \\this.name = name;
        \\}
        \\
        \\fn greet() {
        \\println("Hello, " + this.name);
        \\}
        \\}
        \\
        \\fn repeat(func: function, times: number) {
        \\foreach _ in 0..times {
        \\func();
        \\}
        \\}
        \\
        \\let g = new Greeter("Ziggy");
        \\repeat(g.greet, 3);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\Hello, Ziggy
        \\Hello, Ziggy
        \\Hello, Ziggy
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests basic class declaration and initialization
test "class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\class Person {
        \\let name: string;
        \\let age: number;
        \\
        \\fn ctor(n: string, a: number) {
        \\this.name = n;
        \\this.age = a;
        \\}
        \\}
        \\
        \\let p = new Person("Alice", 42);
        \\println(p.name);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected = "Alice\n";

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests control flow with function return statements
test "return" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\fn test(): number {
        \\let i = 0;
        \\while i < 100 {
        \\println(i);
        \\i = i + 1;
        \\if (i == 3) {
        \\    return i;
        \\}
        \\}
        \\}
        \\
        \\let a = test();
        \\println(a);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\0
        \\1
        \\2
        \\3
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests import (coupled with IEFE) from other files
test "import" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = testing.Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    const source =
        \\println("Importing and immediately invoking add...");
        \\import add from "examples/functions/fn.zlx";
        \\println(add(2, 3));
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\Importing and immediately invoking add...
        \\15
        \\5
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
