test {
    _ = @import("tests/tests.zig");
    _ = @import("tests/app_service_tests.zig");
    _ = @import("tests/coordinator_registry_login_tests.zig");
    _ = @import("tests/coordinator_passive_tests.zig");
    _ = @import("tests/coordinator_scheduling_tests.zig");
    _ = @import("tests/coordinator_reset_tests.zig");
    _ = @import("tests/coordinator_cleanup_roundtrip_tests.zig");
    _ = @import("tests/login_runtime_tests.zig");
    _ = @import("tests/codex_provider_tests.zig");
    _ = @import("tests/provider_child_path_tests.zig");
    _ = @import("tests/oauth_tests.zig");
    _ = @import("tests/keychain_tests.zig");

    _ = @import("tests/ui_module_boundary_tests.zig");
    _ = @import("tests/ui_truthfulness_tests.zig");
    _ = @import("tests/ui_tray_bridge_tests.zig");
    _ = @import("tests/proxy_ui_tests.zig");

    _ = @import("tests/reset_engine_tests.zig");
    _ = @import("tests/operation_scheduler_tests.zig");
    _ = @import("tests/attempt_ledger_tests.zig");
    _ = @import("tests/snapshot_book_tests.zig");

    _ = @import("tests/proxy_control_tests.zig");
    _ = @import("tests/proxy_import_runner_tests.zig");
    _ = @import("tests/proxy_service_tests.zig");
}
