const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("spoon", .{
        .root_source_file = b.path("import.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_source_file = b.path("test_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&tests.step);
}
