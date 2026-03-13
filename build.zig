const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const framework_mod = b.addModule("framework", .{
        .root_source_file = .{ .cwd_relative = "../framework/src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.addModule("ourclaw", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("framework", framework_mod);

    const exe = b.addExecutable(.{
        .name = "ourclaw",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("ourclaw", lib_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the ourclaw executable");
    run_step.dependOn(&run_cmd.step);

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    root_tests.root_module.addImport("framework", framework_mod);
    root_tests.root_module.addImport("ourclaw", lib_mod);

    const run_root_tests = b.addRunArtifact(root_tests);

    const smoke_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/smoke.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    smoke_tests.root_module.addImport("framework", framework_mod);
    smoke_tests.root_module.addImport("ourclaw", lib_mod);

    const run_smoke_tests = b.addRunArtifact(smoke_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_smoke_tests.step);
}
