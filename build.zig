const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // Module
    const zig_fsrs_module = b.addModule("zig-fsrs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Examples
    const vaxis_dep = b.dependency("vaxis", .{
        .optimize = optimize,
        .target = target,
    });
    const Example = enum { simple, tui };
    const example_option = b.option(Example, "example", "Example to run (default: simple)") orelse .simple;
    const example_step = b.step("example", "Run example");
    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{t}.zig", .{example_option})),
            .target = target,
            .optimize = optimize,
            .imports = switch (example_option) {
                .simple => &.{
                    .{ .name = "zig-fsrs", .module = zig_fsrs_module },
                },
                .tui => &.{
                    .{ .name = "zig-fsrs", .module = zig_fsrs_module },
                    .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
                },
            },
        }),
    });

    const example_run = b.addRunArtifact(example);
    example_step.dependOn(&example_run.step);

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-fsrs", .module = zig_fsrs_module },
            },
        }),
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
