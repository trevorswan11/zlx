const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Exe module configuration
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "zlx",
        .root_module = exe_mod,
    });

    // zig-regex module
    const regex_mod = b.addModule("regxp", .{
        .root_source_file = b.path("libs/zig-regex/src/regex.zig"),
    });
    exe.root_module.addImport("regxp", regex_mod);

    // Add steps
    addRunStep(b, exe);
    addTestStep(b, exe_mod);
    addFmtStep(b);

    b.installArtifact(exe);
}

fn addRunStep(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allows the user to use zig build run with command line arguments following '--'
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addTestStep(b: *std.Build, exe_mod: *std.Build.Module) void {
    const test_step = b.step("test", "Run unit tests");
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn addFmtStep(b: *std.Build) void {
    // Format the build script
    const lint_build = b.addSystemCommand(&[_][]const u8{
        "zig", "fmt", "build.zig",
    });

    // Format source directory
    const lint_source = b.addSystemCommand(&[_][]const u8{
        "zig", "fmt", "src",
    });

    const step = b.step("lint", "Check formatting of Zig source files");
    step.dependOn(&lint_build.step);
    step.dependOn(&lint_source.step);
}
