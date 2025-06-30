const std = @import("std");
pub const testing = std.testing;

pub const parser = @import("../parser/parser.zig");
pub const ast = @import("../parser/ast.zig");
pub const interpreter = @import("../interpreter/interpreter.zig");
pub const driver = @import("../utils/driver.zig");

pub const eval = interpreter.eval;
pub const Environment = interpreter.Environment;
pub const Value = interpreter.Value;

pub const expect = testing.expect;
pub const expectEqual = testing.expectEqual;
pub const expectApproxEqAbs = testing.expectApproxEqAbs;
pub const expectEqualStrings = std.testing.expectEqualStrings;
pub const expectEqualSlices = std.testing.expectEqualSlices;
pub const expectError = std.testing.expectError;

/// Returns the test allocator. This should only be used in temporary test programs
pub fn allocator() std.mem.Allocator {
    return testing.allocator;
}

/// Calls the parser's parse method on the source, removing parser include in
pub fn parse(alloc: std.mem.Allocator, source: []const u8) !*ast.Stmt {
    return try parser.parse(alloc, source);
}

// Tests basic parsing of a test file with no statement evaluation or interpretation.
// This is the example language test Written by tylerlaceby
test "ast_check" {
    var arena = std.heap.ArenaAllocator.init(allocator());
    const alloc = arena.allocator();
    defer arena.deinit();

    var env = Environment.init(alloc, null);
    defer env.deinit();

    var output_buffer = std.ArrayList(u8).init(alloc);
    defer output_buffer.deinit();
    const writer = output_buffer.writer().any();
    driver.setWriters(writer);

    const source =
        \\import fs;
        \\import time;
        \\
        \\struct DirectoryReader {
        \\  let directoryPath: string;
        \\
        \\  fn mount(directoryPath: string) {
        \\    this.directoryPath = directoryPath;
        \\  }
        \\
        \\  fn readRecentFiles() {
        \\    let allFiles: []string = fs.readDir(this.directoryPath);
        \\    let recentFiles: []string = [];
        \\
        \\    foreach file in allFiles {
        \\      let fullPath: string = path.join(this.directoryPath, file);
        \\      let fileInfo: FileInfo = fs.stat(fullPath);
        \\      if this.isFileRecent(fileInfo.creationTime) {
        \\        recentFiles.push(fullPath);
        \\      }
        \\    }
        \\
        \\    foreach file in recentFiles {
        \\      println(file, fs.stat(file).creationTime);
        \\    }
        \\  }
        \\
        \\  fn isFileRecent(creationTime: Time): boolean {
        \\    let twentyFourHoursAgo: Time = time.now() - time.hours(24);
        \\    creationTime > twentyFourHoursAgo;
        \\  }
        \\}
        \\
        \\fn are(you: sure, pretty: sure): int {
        \\  let cecil: int = 1;
        \\  let omni: sure = you - pretty;
        \\  cecil;
        \\}
        \\
        \\fn main() {
        \\  const directory: string = "/path/to/directory";
        \\  const reader = new DirectoryReader(); // It is not required to use explicit types
        \\  reader.mount(directory);
        \\  reader.readRecentFiles();
        \\}
        \\
        \\main();
    ;

    // Check if the source code passes the parsing step, and fail if error
    _ = parse(alloc, source) catch {
        try expect(false);
    };
}
