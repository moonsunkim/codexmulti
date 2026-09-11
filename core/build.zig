const std = @import("std");

pub fn build(b: *std.Build) void {
    const core_target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
        },
    });
    const core_optimize = b.standardOptimizeOption(.{});
    const requested_provenance = b.option(
        []const u8,
        "core-provenance",
        "cmcore source SHA-256 or complete CODEXMULTI_CORE_SRC_SHA256 marker",
    ) orelse "UNSPECIFIED";
    const core_marker = if (std.mem.startsWith(u8, requested_provenance, "CODEXMULTI_CORE_SRC_SHA256="))
        requested_provenance
    else
        b.fmt("CODEXMULTI_CORE_SRC_SHA256={s}", .{requested_provenance});
    const core_options = b.addOptions();
    core_options.addOption([]const u8, "marker", core_marker);

    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/cmcore.zig"),
        .target = core_target,
        .optimize = core_optimize,
        .link_libc = true,
    });
    core_mod.addImport("core_provenance", core_options.createModule());
    core_mod.export_symbol_names = &.{
        "cm_service_version",
        "cm_service_create",
        "cm_service_destroy",
        "cm_service_submit",
        "cm_service_pump",
        "cm_service_project",
        "cm_service_provenance",
        "cm_service_keychain_probe",
    };
    const core_object = b.addObject(.{
        .name = "cmcore",
        .root_module = core_mod,
        .use_llvm = true,
    });

    core_object.bundle_compiler_rt = true;
    const install_core = b.addInstallLibFile(core_object.getEmittedBin(), "cmcore.o");
    const cmcore_step = b.step("cmcore", "Build the cm.bridge/1 relocatable object");
    cmcore_step.dependOn(&install_core.step);

    const aggregate_test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_root.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .link_libc = true,
    });
    if (b.sysroot) |sysroot| aggregate_test_mod.addSystemFrameworkPath(.{
        .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }),
    });
    aggregate_test_mod.linkFramework("Security", .{});
    aggregate_test_mod.linkFramework("Foundation", .{});
    const all_tests = b.addTest(.{ .root_module = aggregate_test_mod, .use_llvm = true });
    const test_step = b.step("test", "Run the SDK-free core test aggregate");
    test_step.dependOn(&b.addRunArtifact(all_tests).step);
    const missing_string_key_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/strings_missing_key_compile_error.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    missing_string_key_mod.addImport("strings", b.createModule(.{
        .root_source_file = b.path("src/strings.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }));
    const missing_string_key_test = b.addTest(.{ .root_module = missing_string_key_mod });
    missing_string_key_test.expect_errors = .{ .contains = "enum 'strings.StaticKey' has no member named 'not_in_catalog'" };
    test_step.dependOn(&missing_string_key_test.step);

    const bridge_test_step = b.step("test-bridge", "Run the cm.bridge/1 contract gate");
    const bridge_test_roots = [_][]const u8{
        "src/tests/shell_model_tests.zig",
        "src/tests/bridge_contract_tests.zig",
        "src/tests/bridge_fixture_export_tests.zig",
        "src/tests/proxy_launch_runner_tests.zig",
        "src/tests/codex_routing_editor_tests.zig",
        "src/tests/proxy_service_manager_tests.zig",
    };
    for (bridge_test_roots) |root| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(root),
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
        });
        if (std.mem.endsWith(u8, root, "shell_model_tests.zig")) {
            test_mod.addImport("shell_model", b.createModule(.{
                .root_source_file = b.path("src/shell_model.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
            }));
        } else if (std.mem.endsWith(u8, root, "proxy_launch_runner_tests.zig")) {
            test_mod.addImport("proxy_launch_runner", b.createModule(.{
                .root_source_file = b.path("src/proxy_launch_runner.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
            }));
        } else if (std.mem.endsWith(u8, root, "codex_routing_editor_tests.zig")) {
            test_mod.addImport("codex_routing_editor", b.createModule(.{
                .root_source_file = b.path("src/codex_routing_editor.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
            }));
        } else if (std.mem.endsWith(u8, root, "proxy_service_manager_tests.zig")) {
            test_mod.addImport("proxy_service_manager", b.createModule(.{
                .root_source_file = b.path("src/proxy_service_manager.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
            }));
        } else if (std.mem.endsWith(u8, root, "bridge_fixture_export_tests.zig")) {
            test_mod.addImport("bridge_json", b.createModule(.{
                .root_source_file = b.path("src/bridge_json.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
            }));
        } else {
            const test_core_options = b.addOptions();
            test_core_options.addOption([]const u8, "marker", "CODEXMULTI_CORE_SRC_SHA256=TEST-BRIDGE");
            const test_core_mod = b.createModule(.{
                .root_source_file = b.path("src/cmcore.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
                .link_libc = true,
            });
            test_core_mod.addImport("core_provenance", test_core_options.createModule());
            if (b.sysroot) |sysroot| test_core_mod.addSystemFrameworkPath(.{
                .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }),
            });
            test_core_mod.linkFramework("Security", .{});
            test_core_mod.linkFramework("Foundation", .{});
            test_mod.addImport("cmcore", test_core_mod);
        }
        const bridge_tests = b.addTest(.{ .root_module = test_mod, .use_llvm = true });
        bridge_test_step.dependOn(&b.addRunArtifact(bridge_tests).step);
    }

    const fixture_export_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/bridge_fixture_export_tests.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .link_libc = true,
    });
    fixture_export_mod.addImport("bridge_json", b.createModule(.{
        .root_source_file = b.path("src/bridge_json.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }));
    const fixture_exporter = b.addExecutable(.{
        .name = "bridge-fixture-exporter",
        .root_module = fixture_export_mod,
        .use_llvm = true,
    });
    const export_fixtures_step = b.step("export-fixtures", "Regenerate cm.bridge/1 JSON fixtures");
    export_fixtures_step.dependOn(&b.addRunArtifact(fixture_exporter).step);
}
