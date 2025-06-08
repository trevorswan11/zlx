const std = @import("std");

const testing = @import("testing.zig");

// Tests class creation with constructors and method invocation
test "methods" {
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
        \\let g = new Greeter("Ziggy");
        \\println(g.name);
        \\println(g["__class_name"]);
        \\g.greet();
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\Ziggy
        \\Greeter
        \\Hello, Ziggy
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}

// Tests object creation (similar to js) along with the two ways to access properties
test "objects" {
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
        \\let obj1 = { foo: 123 };
        \\println(obj1.foo);
        \\
        \\let obj2 = { 
        \\  foo: 456
        \\};
        \\println(obj2["foo"]);
    ;

    const block = try testing.parse(allocator, source);
    _ = try testing.eval.evalStmt(block, &env);

    const expected =
        \\123
        \\456
        \\
    ;

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
