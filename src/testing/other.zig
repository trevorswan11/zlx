const std = @import("std");

const testing = @import("testing.zig");

// Tests type declarations
test "types" {
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
        \\const foo = 10;
        \\println(typeof foo);
        \\
        \\const bar: number = 10;
        \\println(typeof bar);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\any
        \\number
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests variable declarations and constant enforcement
test "assignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    testing.eval.setWriters(writer);

    // Good use of constants and variable declarations
    var env_pass = testing.Environment.init(allocator, null);
    defer env_pass.deinit();

    const source_pass =
        \\let foo = 45.5;
        \\let bar = foo * 10;
        \\
        \\const isGreater = foo > 10;
        \\println(isGreater);
        \\
        \\let baz = 1;
        \\print("baz: " + baz + " -> ");
        \\baz = "dynamic typing";
        \\println(baz);
    ;

    const block_pass = try testing.parse(allocator, source_pass);
    _ = try testing.eval.evalStmt(block_pass, &env_pass);

    const expected =
        \\true
        \\baz: 1 -> dynamic typing
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);

    // Poor use of constant keyword
    var env_fail = testing.Environment.init(allocator, null);
    defer env_fail.deinit();

    const source_fail =
        \\const a = 0;
        \\a = 2;
    ;

    const block_fail = try testing.parse(allocator, source_fail);
    const err_out = testing.eval.evalStmt(block_fail, &env_fail);

    try testing.expectError(error.ReassignmentToConstantVariable, err_out);
}

// Tests multiline string declarations
test "multiline_string" {
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
        \\let s = """This is
        \\a multiline
        \\string""";
        \\println(s);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\This is
        \\a multiline
        \\string
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests match's ability to switch on input
test "match_stmt" {
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
        \\let x = 3;
        \\
        \\match x {
        \\    1 => println("one");
        \\    2 => println("two");
        \\    3 => {
        \\        println("three");
        \\        println("more");
        \\    },
        \\    _ => println("default");
        \\}
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\three
        \\more
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests match's ability to switch on input and act as an expression to be used in assignment
test "match_expr" {
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
        \\let x = 3;
        \\
        \\let y = match x {
        \\    3 => 4,
        \\    _ => 100,
        \\};
        \\
        \\println(y);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\4
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
