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

// Tests single import from other files
test "import_single" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    // Good use of selective import statement
    var env_pass = testing.Environment.init(allocator, null);
    defer env_pass.deinit();

    const source_pass =
        \\import add from "examples/functions/fn.zlx";
        \\
        \\println(add(2, 3));
    ;

    const block_pass = try testing.parse(allocator, source_pass);
    _ = try testing.eval.evalStmt(block_pass, &env_pass);

    const expected =
        \\5
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);

    // Poor use of selective import, x was not requested
    var env_fail_one = testing.Environment.init(allocator, null);
    defer env_fail_one.deinit();

    const source_fail_one =
        \\import add from "examples/functions/fn.zlx";
        \\
        \\println(x);
    ;

    const block_fail_one = try testing.parse(allocator, source_fail_one);
    const err_out_one = testing.eval.evalStmt(block_fail_one, &env_fail_one);

    try testing.expectError(error.UndefinedValue, err_out_one);

    // Poor use of selective import, sub is not defined
    var env_fail_two = testing.Environment.init(allocator, null);
    defer env_fail_two.deinit();

    const source_fail_two =
        \\import sub from "examples/functions/fn.zlx";
    ;

    const block_fail_two = try testing.parse(allocator, source_fail_two);
    const err_out_two = testing.eval.evalStmt(block_fail_two, &env_fail_two);

    try testing.expectError(error.UndefinedIdentifier, err_out_two);
}

// Tests wildcard (*) imports from other files
test "import_wildcard" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    // Good use of wildcard import statement
    var env_pass = testing.Environment.init(allocator, null);
    defer env_pass.deinit();

    const source_pass =
        \\import * from "examples/functions/fn.zlx";
        \\
        \\println(add(30, -3)); // 27
        \\println(x); // 2
        \\println(y); // 54
    ;

    const block_pass = try testing.parse(allocator, source_pass);
    _ = try testing.eval.evalStmt(block_pass, &env_pass);

    const expected =
        \\27
        \\2
        \\54
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);

    // Poor use of selective import, sub is not defined in scope
    var env_fail = testing.Environment.init(allocator, null);
    defer env_fail.deinit();

    const source_fail =
        \\import * from "examples/functions/fn.zlx";
        \\
        \\println(sub(30, -3));
    ;

    const block_fail = try testing.parse(allocator, source_fail);
    const err_out = testing.eval.evalStmt(block_fail, &env_fail);

    try testing.expectError(error.UndefinedValue, err_out);
}

// Tests file imports that have imports in them
test "import_recursive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    // Use of recursive import on a file with a selective import statement
    var output_buffer_single = std.ArrayList(u8).init(allocator);
    defer output_buffer_single.deinit();
    const writer_single = output_buffer_single.writer().any();
    testing.eval.setWriters(writer_single);

    var env_single = testing.Environment.init(allocator, null);
    defer env_single.deinit();

    const source_single =
        \\import add from "examples/functions/import_single.zlx";
        \\
        \\println(add(-92, 24));
    ;

    const block_single = try testing.parse(allocator, source_single);
    _ = try testing.eval.evalStmt(block_single, &env_single);

    const expected =
        \\-68
        \\
    ;

    const actual = output_buffer_single.items;
    try testing.expectEqualStrings(expected, actual);

    // Use of recursive import on a file with a wildcard import statement
    var output_buffer_wildcard = std.ArrayList(u8).init(allocator);
    defer output_buffer_wildcard.deinit();
    const writer_wildcard = output_buffer_wildcard.writer().any();
    testing.eval.setWriters(writer_wildcard);

    var env_wildcard = testing.Environment.init(allocator, null);
    defer env_wildcard.deinit();

    const source_wildcard =
        \\import add from "examples/functions/import_wildcard.zlx";
        \\
        \\println(add(-92, 25));
    ;

    const block_wildcard = try testing.parse(allocator, source_wildcard);
    _ = try testing.eval.evalStmt(block_wildcard, &env_wildcard);

    const expected_wildcard =
        \\-67
        \\
    ;

    const actual_wildcard = output_buffer_wildcard.items;
    try testing.expectEqualStrings(expected_wildcard, actual_wildcard);
}
