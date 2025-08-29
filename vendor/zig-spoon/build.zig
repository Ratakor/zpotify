const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const spoon_module = b.addModule("spoon", .{
        .root_source_file = b.path("import.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = spoon_module });
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&tests.step);
}
