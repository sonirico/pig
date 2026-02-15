const std = @import("std");

fn addPathIfExists(exe: *std.Build.Step.Compile, path: []const u8, is_include: bool) void {
    const stat = std.fs.cwd().statFile(path) catch return;
    if (stat.kind == .directory) {
        if (is_include) {
            exe.addIncludePath(.{ .cwd_relative = path });
        } else {
            exe.addLibraryPath(.{ .cwd_relative = path });
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add strip option
    const strip = b.option(bool, "strip", "Strip debug symbols") orelse false;
    // Force static linking (use with musl/Alpine and static libvips)
    const static = b.option(bool, "static", "Link statically (no runtime deps)") orelse false;

    // Add zli dependency
    const zli = b.dependency("zli", .{
        .target = target,
        .optimize = optimize,
    });

    // --- Lib: shared module for CLI and external consumers ---
    const pig_lib = b.addModule("pig", .{
        .root_source_file = b.path("src/lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    pig_lib.addCMacro("_GNU_SOURCE", "1");
    pig_lib.addCMacro("_DEFAULT_SOURCE", "1");
    pig_lib.addCMacro("_POSIX_C_SOURCE", "200809L");
    pig_lib.addCMacro("_FILE_OFFSET_BITS", "64");
    if (static) {
        pig_lib.addIncludePath(.{ .cwd_relative = "/opt/static/include" });
        pig_lib.addIncludePath(.{ .cwd_relative = "/opt/static/include/glib-2.0" });
        pig_lib.addIncludePath(.{ .cwd_relative = "/opt/static/lib/glib-2.0/include" });
    }
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/include" });
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/include/vips" });
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/lib/glib-2.0/include" }); // Alpine
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/lib64/glib-2.0/include" });
    pig_lib.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });

    // --- CLI executable (consumes pig lib) ---
    const exe = b.addExecutable(.{
        .name = "pig",
        .root_module = b.addModule("pig-cli", .{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }),
    });
    exe.root_module.addImport("pig", pig_lib);
    exe.root_module.addImport("zli", zli.module("zli"));

    // Add C defines for cross-compilation compatibility
    exe.root_module.addCMacro("_GNU_SOURCE", "1");
    exe.root_module.addCMacro("_DEFAULT_SOURCE", "1");
    exe.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
    exe.root_module.addCMacro("_FILE_OFFSET_BITS", "64");

    // Link libvips for image processing
    exe.linkSystemLibrary("vips");
    exe.linkSystemLibrary("glib-2.0");
    exe.linkSystemLibrary("gobject-2.0");
    exe.linkSystemLibrary("gio-2.0");
    exe.linkSystemLibrary("gmodule-2.0");
    exe.linkLibC();
    if (static) {
        exe.linkage = .static;
        addPathIfExists(exe, "/opt/static/include", true);
        addPathIfExists(exe, "/opt/static/lib", false);
        // In static mode, only use /opt/static — system lib paths contain .so files
        // that cause "using shared libraries requires dynamic linking" errors.
        addPathIfExists(exe, "/opt/static/include/glib-2.0", true);
        addPathIfExists(exe, "/opt/static/lib/glib-2.0/include", true);
    } else {
        addPathIfExists(exe, "/usr/local/lib", false);
        addPathIfExists(exe, "/usr/lib/x86_64-linux-gnu", false);
        addPathIfExists(exe, "/usr/lib", false);
    }

    // Include paths are always safe (headers only, no .so)
    addPathIfExists(exe, "/usr/local/include", true);
    addPathIfExists(exe, "/usr/include", true);
    addPathIfExists(exe, "/usr/include/vips", true);
    addPathIfExists(exe, "/usr/include/glib-2.0", true);
    addPathIfExists(exe, "/usr/lib/glib-2.0/include", true); // Alpine
    addPathIfExists(exe, "/usr/lib64/glib-2.0/include", true);
    addPathIfExists(exe, "/usr/lib/x86_64-linux-gnu/glib-2.0/include", true);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Unit tests (run tests from lib + CLI tree)
    const unit_tests = b.addTest(.{
        .root_module = b.addModule("test", .{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("pig", pig_lib);
    unit_tests.root_module.addImport("zli", zli.module("zli"));
    unit_tests.root_module.addCMacro("_GNU_SOURCE", "1");
    unit_tests.root_module.addCMacro("_DEFAULT_SOURCE", "1");
    unit_tests.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
    unit_tests.root_module.addCMacro("_FILE_OFFSET_BITS", "64");
    unit_tests.linkSystemLibrary("vips");
    unit_tests.linkSystemLibrary("glib-2.0");
    unit_tests.linkSystemLibrary("gobject-2.0");
    unit_tests.linkSystemLibrary("gio-2.0");
    unit_tests.linkSystemLibrary("gmodule-2.0");
    unit_tests.linkLibC();
    addPathIfExists(unit_tests, "/usr/local/include", true);
    addPathIfExists(unit_tests, "/usr/include", true);
    addPathIfExists(unit_tests, "/usr/include/vips", true);
    addPathIfExists(unit_tests, "/usr/include/glib-2.0", true);
    addPathIfExists(unit_tests, "/usr/lib64/glib-2.0/include", true);
    addPathIfExists(unit_tests, "/usr/lib/x86_64-linux-gnu/glib-2.0/include", true);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Lib tests (tests inside the pig library: vips_custom, format_options, etc.)
    const lib_tests = b.addTest(.{
        .root_module = b.addModule("lib-test", .{
            .root_source_file = b.path("src/lib/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_tests.root_module.addCMacro("_GNU_SOURCE", "1");
    lib_tests.root_module.addCMacro("_DEFAULT_SOURCE", "1");
    lib_tests.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
    lib_tests.root_module.addCMacro("_FILE_OFFSET_BITS", "64");
    lib_tests.linkSystemLibrary("vips");
    lib_tests.linkSystemLibrary("glib-2.0");
    lib_tests.linkSystemLibrary("gobject-2.0");
    lib_tests.linkSystemLibrary("gio-2.0");
    lib_tests.linkSystemLibrary("gmodule-2.0");
    lib_tests.linkLibC();
    addPathIfExists(lib_tests, "/usr/local/include", true);
    addPathIfExists(lib_tests, "/usr/include", true);
    addPathIfExists(lib_tests, "/usr/include/vips", true);
    addPathIfExists(lib_tests, "/usr/include/glib-2.0", true);
    addPathIfExists(lib_tests, "/usr/lib64/glib-2.0/include", true);
    addPathIfExists(lib_tests, "/usr/lib/x86_64-linux-gnu/glib-2.0/include", true);

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const lib_test_step = b.step("lib-test", "Run library tests (vips_custom, format_options)");
    lib_test_step.dependOn(&run_lib_tests.step);
    // Also include lib tests in the main test step
    test_step.dependOn(&run_lib_tests.step);

    // Integration tests: snapshot-based runner in Zig (no bash)
    const integration_exe = b.addExecutable(.{
        .name = "integration_test",
        .root_module = b.addModule("integration-test", .{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_integration = b.addRunArtifact(integration_exe);
    run_integration.step.dependOn(b.getInstallStep());
    run_integration.setCwd(b.path("."));
    run_integration.addArg("--pig");
    run_integration.addArg("zig-out/bin/pig");
    const integration_step = b.step("integration-test", "Run integration tests (snapshot-based). Use -Dupdate=true to refresh snapshots.");
    integration_step.dependOn(&run_integration.step);

    // Optional: update snapshots (pass -Dupdate to refresh tests/snapshots/expected.json)
    const update_snapshots = b.option(bool, "update", "Update integration snapshots when results improve") orelse false;
    if (update_snapshots) {
        run_integration.addArg("--update");
    }
}
