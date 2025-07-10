const std = @import("std");

const ast = @import("../../parser/ast.zig");
const interpreter = @import("../../interpreter/interpreter.zig");
const driver = @import("../../utils/driver.zig");
const builtins = @import("../builtins.zig");

const eval = interpreter.eval;
const Environment = interpreter.Environment;
const Value = interpreter.Value;

const StdMethod = builtins.StdMethod;
const StdCtor = builtins.StdCtor;

const expectValues = builtins.expectValues;
const expectNumberArgs = builtins.expectNumberArgs;
const expectArrayArgs = builtins.expectArrayArgs;
const expectStringArgs = builtins.expectStringArgs;

const ThreadInstance = struct {
    thread: std.Thread,
    done: *bool,
};

fn getThreadInstance(this: *Value) !*ThreadInstance {
    const internal = this.std_instance.fields.get("__internal") orelse
        return error.MissingInternalField;
    return @ptrCast(@alignCast(internal.*.typed_val.value));
}

var THREAD_METHODS: std.StringHashMap(StdMethod) = undefined;
var THREAD_TYPE: Value = undefined;

pub fn load(allocator: std.mem.Allocator) !Value {
    THREAD_METHODS = std.StringHashMap(StdMethod).init(allocator);
    try THREAD_METHODS.put("join", threadJoin);
    try THREAD_METHODS.put("done", threadDone);

    THREAD_TYPE = .{
        .std_struct = .{
            .name = "thread",
            .constructor = threadConstructor,
            .methods = THREAD_METHODS,
        },
    };

    return THREAD_TYPE;
}

const ThreadContext = struct {
    fn_val: Value,
    args: []*ast.Expr,
    env: *Environment,
    done: *bool,
};

fn threadEntry(ctx: *ThreadContext) void {
    _ = ctx.fn_val.callFn(ctx.args, ctx.env) catch {};
    ctx.done.* = true;
}

fn threadConstructor(args: []const *ast.Expr, env: *Environment) !Value {
    const writer_err = driver.getWriterErr();
    const fn_val = (try expectValues(args[0..1], env, 1, "thread", "ctor", "fn_val, args..."))[0];

    if (!Value.isCallable(fn_val)) {
        try writer_err.print("thread.ctor(fn_val, args...): fn_val must be callable but {s} is not\n", .{@tagName(fn_val)});
        return error.ThreadCtorRequiresCallable;
    }

    const cloned_env = try interpreter.cloneEnvironment(env);
    const fn_args = try cloned_env.allocator.dupe(*ast.Expr, args[1..]);

    const copied_args = try cloned_env.allocator.alloc(*ast.Expr, fn_args.len);
    for (fn_args, 0..) |arg, i| {
        copied_args[i] = arg;
    }

    const done_ptr = try cloned_env.allocator.create(bool);
    done_ptr.* = false;

    const context_ptr = try cloned_env.allocator.create(ThreadContext);
    context_ptr.* = .{
        .fn_val = fn_val,
        .args = copied_args,
        .env = cloned_env,
        .done = done_ptr,
    };
    const thread = try std.Thread.spawn(.{}, threadEntry, .{context_ptr});

    const wrapped = try env.allocator.create(ThreadInstance);
    wrapped.* = .{
        .thread = thread,
        .done = done_ptr,
    };

    const internal_val = try env.allocator.create(Value);
    internal_val.* = .{
        .typed_val = .{
            .value = @ptrCast(@alignCast(wrapped)),
            ._type = "thread",
        },
    };

    var fields = std.StringHashMap(*Value).init(env.allocator);
    try fields.put("__internal", internal_val);

    const type_ptr = try env.allocator.create(Value);
    type_ptr.* = THREAD_TYPE;

    return .{
        .std_instance = .{
            ._type = type_ptr,
            .fields = fields,
        },
    };
}

fn threadJoin(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "thread", "join", "");
    const inst = try getThreadInstance(this);
    inst.thread.join();
    return .nil;
}

fn threadDone(this: *Value, args: []const *ast.Expr, env: *Environment) !Value {
    _ = try expectValues(args, env, 0, "thread", "done", "");
    const inst = try getThreadInstance(this);
    return .{
        .boolean = inst.done.*,
    };
}

// === TESTING ===

const testing = @import("../../testing/testing.zig");

test "thread_builtin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(allocator, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriters(writer);

    const source =
        \\import thread;
        \\
        \\let say = fn(msg) {
        \\    println(format("msg: {}", msg));
        \\};
        \\let t = new thread(say, "hello from thread!");
        \\t.join();
        \\let is_done = t.done();
    ;

    const expected =
        \\msg: hello from thread!
        \\
    ;

    const block = try testing.parse(allocator, source);
    _ = try eval.evalStmt(block, &env);

    const is_done = try env.get("is_done");
    try testing.expect(is_done == .boolean);
    try testing.expect(is_done.boolean);

    const actual = output_buffer.items;
    try testing.expectEqualStrings(expected, actual);
}
