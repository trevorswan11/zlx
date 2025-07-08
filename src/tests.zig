const std = @import("std");

test {
    // Initialization for reserved identifiers
    _ = try @import("lexer/token.zig").Token.getReservedMap(std.heap.page_allocator);

    // Builtin Modules - Tests located with source code
    _ = @import("builtins/fns.zig");
    _ = @import("builtins/modules/array.zig");
    _ = @import("builtins/modules/debug.zig");
    _ = @import("builtins/modules/fs.zig");
    _ = @import("builtins/modules/math.zig");
    _ = @import("builtins/modules/path.zig");
    _ = @import("builtins/modules/random.zig");
    _ = @import("builtins/modules/string.zig");
    _ = @import("builtins/modules/sys.zig");
    _ = @import("builtins/modules/time.zig");
    _ = @import("builtins/modules/csv.zig");
    _ = @import("builtins/modules/json.zig");
    _ = @import("builtins/modules/stat.zig");

    // Tooling & Helper Files
    _ = @import("builtins/helpers/statistics.zig");
    _ = @import("utils/compression.zig");
    _ = @import("utils/hex.zig");
    _ = @import("utils/fmt.zig");

    // Builtin Standard Library Structs
    _ = @import("builtins/types/adjacency_list.zig");
    _ = @import("builtins/types/adjacency_matrix.zig");
    _ = @import("builtins/types/array_list.zig");
    _ = @import("builtins/types/deque.zig");
    _ = @import("builtins/types/graph.zig");
    _ = @import("builtins/types/hash_map.zig");
    _ = @import("builtins/types/hash_set.zig");
    _ = @import("builtins/types/list.zig");
    _ = @import("builtins/types/priority_queue.zig");
    _ = @import("builtins/types/queue.zig");
    _ = @import("builtins/types/stack.zig");
    _ = @import("builtins/types/treap.zig");
    _ = @import("builtins/types/sqlite.zig");

    // General Behavior - Tests located in `testing` directory
    _ = @import("testing/testing.zig");
    _ = @import("testing/structs_objects.zig");
    _ = @import("testing/functions.zig");
    _ = @import("testing/loops.zig");
    _ = @import("testing/operations.zig");
    _ = @import("testing/other.zig");
}
