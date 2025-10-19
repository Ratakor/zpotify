//! Based on https://github.com/zigtools/zls/blob/master/build.zig under MIT License.

const std = @import("std");
const builtin = @import("builtin");

const program_name = "zpotify";

/// Must match the `version` in `build.zig.zon`.
/// Remove `.pre` when tagging a new release and add it back on the next development cycle.
const version: std.SemanticVersion = .{ .major = 0, .minor = 4, .patch = 0 };

const release_targets = [_]std.Target.Query{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .freebsd },
    // .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const single_threaded = b.option(bool, "single-threaded", "Build a single threaded Executable");
    const pie = b.option(bool, "pie", "Build a Position Independent Executable");
    const strip = b.option(bool, "strip", "Strip executable");
    const use_llvm = b.option(bool, "use-llvm", "Use Zig's llvm code backend");
    const image_support = b.option(bool, "image-support", "Build with image support (requires chafa and libjpeg)") orelse false;

    const resolved_version = getVersion(b);

    const build_options = blk: {
        const options = b.addOptions();
        options.addOption([]const u8, "program_name", program_name);
        options.addOption(std.SemanticVersion, "version", resolved_version);
        options.addOption([]const u8, "version_string", b.fmt("{f}", .{resolved_version}));
        options.addOption(bool, "image_support", image_support);
        break :blk options.createModule();
    };

    // zig build release
    // -Dimage-support=false -Dstrip=true --release=fast
    var release_artifacts: [release_targets.len]*std.Build.Step.Compile = undefined;
    for (release_targets, &release_artifacts) |target_query, *artifact| {
        const release_target = b.resolveTargetQuery(target_query);

        const lib_module = b.createModule(.{
            .root_source_file = b.path("lib/root.zig"),
            .target = release_target,
            .optimize = optimize,
        });
        const axe_module = b.lazyDependency("axe", .{
            .target = release_target,
            .optimize = optimize,
        }).?.module("axe");
        const spoon_module = b.lazyDependency("spoon", .{
            .target = release_target,
            .optimize = optimize,
        }).?.module("spoon");

        const exe_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = release_target,
            .optimize = optimize,
            .single_threaded = single_threaded,
            .pic = pie,
            .strip = strip,
            .omit_frame_pointer = strip,
            .imports = &.{
                .{ .name = "build_options", .module = build_options },
                .{ .name = "zpotify", .module = lib_module },
                .{ .name = "axe", .module = axe_module },
                .{ .name = "spoon", .module = spoon_module },
            },
        });

        artifact.* = b.addExecutable(.{
            .name = program_name,
            .root_module = exe_module,
            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        if (image_support) {
            artifact.*.linkLibC();
            artifact.*.linkSystemLibrary("glib-2.0");
            artifact.*.linkSystemLibrary("chafa");
            artifact.*.linkSystemLibrary("libjpeg");
        }
    }
    release(b, &release_artifacts, resolved_version);

    const lib_module = b.addModule("zpotify", .{
        .root_source_file = b.path("lib/root.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .pic = pie,
        .strip = strip,
        .omit_frame_pointer = strip,
    });

    // zig build lib
    const lib = b.addLibrary(.{
        .name = "zpotify",
        .linkage = .static,
        .root_module = lib_module,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    const lib_step = b.step("lib", "Build the library");
    lib_step.dependOn(&b.addInstallArtifact(lib, .{}).step);

    const axe_module = b.lazyDependency("axe", .{
        .target = target,
        .optimize = optimize,
    }).?.module("axe");
    const spoon_module = b.lazyDependency("spoon", .{
        .target = target,
        .optimize = optimize,
    }).?.module("spoon");

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .pic = pie,
        .strip = strip,
        .omit_frame_pointer = strip,
        .imports = &.{
            .{ .name = "build_options", .module = build_options },
            .{ .name = "zpotify", .module = lib_module },
            .{ .name = "axe", .module = axe_module },
            .{ .name = "spoon", .module = spoon_module },
        },
    });

    // zig build
    const exe = b.addExecutable(.{
        .name = program_name,
        .root_module = exe_module,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    if (image_support) {
        exe.linkLibC();
        exe.linkSystemLibrary("glib-2.0");
        exe.linkSystemLibrary("chafa");
        exe.linkSystemLibrary("libjpeg");
    }
    b.installArtifact(exe);

    // zib build run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // zib build test
    const tests = b.addTest(.{ .root_module = exe_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    // zig build fmt
    const fmt_step = b.step("fmt", "Format all source files");
    fmt_step.dependOn(&b.addFmt(.{ .paths = &.{
        "build.zig",
        "src",
        "vendor/zig-spoon",
    } }).step);
}

/// Returns `MAJOR.MINOR.PATCH-dev` when `git describe` failed.
fn getVersion(b: *std.Build) std.SemanticVersion {
    const version_string = b.option([]const u8, "version-string", "Override the version of this build. Must be a semantic version.");
    if (version_string) |semver_string| {
        return std.SemanticVersion.parse(semver_string) catch |err| {
            std.debug.panic("Expected -Dversion-string={s} to be a semantic version: {}", .{ semver_string, err });
        };
    }

    if (version.pre == null and version.build == null) return version;

    const argv: []const []const u8 = &.{
        "git", "-C", b.pathFromRoot("."), "--git-dir", ".git", "describe", "--match", "*.*.*", "--tags",
    };
    var code: u8 = undefined;
    const git_describe_untrimmed = b.runAllowFail(argv, &code, .Ignore) catch |err| {
        const argv_joined = std.mem.join(b.allocator, " ", argv) catch @panic("OOM");
        std.log.warn(
            \\Failed to run git describe to resolve version: {}
            \\command: {s}
            \\
            \\Consider passing the -Dversion-string flag to specify the version.
        , .{ err, argv_joined });
        return version;
    };

    const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => {
            // Tagged release version (e.g. 0.10.0).
            std.debug.assert(std.mem.eql(u8, git_describe, b.fmt("{f}", .{version}))); // tagged release must match version string
            return version;
        },
        2 => {
            // Untagged development build (e.g. 0.10.0-dev.216+34ce200).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            var tagged_ancestor = it.first();
            if (tagged_ancestor[0] == 'v') {
                tagged_ancestor = tagged_ancestor[1..];
            }
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            const ancestor_ver = std.SemanticVersion.parse(tagged_ancestor) catch unreachable;
            if (version.order(ancestor_ver) != .gt) {
                std.debug.panic("Version in build.zig ({f}) must be greater than the latest git tag ({s})", .{ version, tagged_ancestor });
            }
            std.debug.assert(std.mem.startsWith(u8, commit_id, "g")); // commit hash is prefixed with a 'g'

            return .{
                .major = version.major,
                .minor = version.minor,
                .patch = version.patch,
                .pre = b.fmt("dev.{s}", .{commit_height}),
                .build = commit_id[1..],
            };
        },
        else => {
            std.debug.panic("Unexpected 'git describe' output: '{s}'\n", .{git_describe});
        },
    }
}

/// - compile binaries with different targets
/// - compress them (.tar.xz or .zip)
/// - install artifacts to `./zig-out`
fn release(b: *std.Build, release_artifacts: []const *std.Build.Step.Compile, release_version: std.SemanticVersion) void {
    const release_step = b.step("release", "Build and compress all release artifacts");
    const install_dir: std.Build.InstallDir = .{ .custom = "artifacts" };
    const FileExtension = enum { zip, @"tar.xz" };

    if (release_version.pre != null and release_version.build == null) {
        release_step.addError("Cannot build release because the version could not be resolved", .{}) catch @panic("OOM");
        return;
    }

    for (release_artifacts) |exe| {
        const resolved_target = exe.root_module.resolved_target.?.result;
        const is_windows = resolved_target.os.tag == .windows;
        const exe_name = b.fmt("{s}{s}", .{ exe.name, resolved_target.exeFileExt() });
        const extension: FileExtension = if (is_windows) .zip else .@"tar.xz";

        const cpu_arch_name = @tagName(resolved_target.cpu.arch);
        const file_name = b.fmt(program_name ++ "-{t}-{s}-{f}.{t}", .{
            resolved_target.os.tag,
            cpu_arch_name,
            release_version,
            extension,
        });
        var file_path: std.Build.LazyPath = undefined;

        const compress_cmd = std.Build.Step.Run.create(b, "compress artifact");
        compress_cmd.clearEnvironment();
        switch (extension) {
            .zip => {
                compress_cmd.addArgs(&.{ "7z", "a", "-mx=9" });
                file_path = compress_cmd.addOutputFileArg(file_name);
                compress_cmd.addArtifactArg(exe);
                compress_cmd.addFileArg(exe.getEmittedPdb());
                compress_cmd.addFileArg(b.path("LICENSE"));
                compress_cmd.addFileArg(b.path("README.md"));
            },
            .@"tar.xz" => {
                compress_cmd.setEnvironmentVariable("PATH", b.graph.env_map.get("PATH") orelse "");
                compress_cmd.setEnvironmentVariable("XZ_OPT", "-9");
                compress_cmd.addArgs(&.{ "tar", "caf" });
                file_path = compress_cmd.addOutputFileArg(file_name);
                compress_cmd.addPrefixedDirectoryArg("-C", exe.getEmittedBinDirectory());
                compress_cmd.addArg(exe_name);

                compress_cmd.addPrefixedDirectoryArg("-C", b.path("."));
                compress_cmd.addArg("LICENSE");
                compress_cmd.addArg("README.md");

                compress_cmd.addArgs(&.{
                    "--sort=name",
                    "--numeric-owner",
                    "--owner=0",
                    "--group=0",
                    "--mtime=1970-01-01",
                });
            },
        }

        const install_tarball = b.addInstallFileWithDir(file_path, install_dir, file_name);
        release_step.dependOn(&install_tarball.step);
    }
}
