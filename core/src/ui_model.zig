const contracts = @import("ui_contracts.zig");
const projection = @import("ui_projection.zig");
const format = @import("ui_format.zig");
const reset = @import("ui_reset.zig");

pub const AuthState = contracts.AuthState;
pub const Freshness = contracts.Freshness;
pub const Surface = contracts.Surface;
pub const ClaudeTrayWindow = contracts.ClaudeTrayWindow;
pub const SettingsTab = contracts.SettingsTab;
pub const Appearance = contracts.Appearance;
pub const CodexUsageWindow = contracts.CodexUsageWindow;
pub const Language = contracts.Language;
pub const AutoUpdateState = contracts.AutoUpdateState;
pub const TimeZone = contracts.TimeZone;
pub const UnifiedOrderSource = contracts.UnifiedOrderSource;
pub const UnifiedFailoverState = contracts.UnifiedFailoverState;
pub const ProxyReachability = contracts.ProxyReachability;
pub const ProxyAccountState = contracts.ProxyAccountState;
pub const ProxyWork = contracts.ProxyWork;
pub const ProxySyncState = contracts.ProxySyncState;
pub const ProxyAttemptResult = contracts.ProxyAttemptResult;
pub const ProxyServiceState = contracts.ProxyServiceState;
pub const CodexRoutingState = contracts.CodexRoutingState;
pub const OnboardingStepKind = contracts.OnboardingStepKind;

pub const max_rows = contracts.max_rows;
pub const max_windows_per_row = contracts.max_windows_per_row;
pub const max_tray_items = contracts.max_tray_items;
pub const max_line_bytes = contracts.max_line_bytes;
pub const names_capacity = contracts.names_capacity;
pub const text_capacity = contracts.text_capacity;
pub const max_title_bytes = contracts.max_title_bytes;
pub const tray_fixed_items = contracts.tray_fixed_items;

pub const WindowFact = contracts.WindowFact;
pub const AccountFact = contracts.AccountFact;
pub const ResetProxyClear = contracts.ResetProxyClear;
pub const ProxySettingsDraft = contracts.ProxySettingsDraft;
pub const ProxyAccountFact = contracts.ProxyAccountFact;
pub const ProxyAccountView = contracts.ProxyAccountView;
pub const ProxyFact = contracts.ProxyFact;
pub const ProxyServiceFact = contracts.ProxyServiceFact;
pub const OnboardingStepView = contracts.OnboardingStepView;
pub const OnboardingNextAction = contracts.OnboardingNextAction;
pub const WindowView = contracts.WindowView;
pub const AccountView = contracts.AccountView;
pub const UsageRow = contracts.UsageRow;
pub const CreditOffer = contracts.CreditOffer;
pub const Inspector = contracts.Inspector;
pub const RowChip = contracts.RowChip;
pub const WindowCell = contracts.WindowCell;
pub const AccountRowView = contracts.AccountRowView;
pub const UnifiedRowView = contracts.UnifiedRowView;
pub const SettingsView = contracts.SettingsView;
pub const ProxyTableRow = contracts.ProxyTableRow;
pub const TrayItem = contracts.TrayItem;

pub const tray_command_refresh_all = contracts.tray_command_refresh_all;
pub const tray_command_open_details = contracts.tray_command_open_details;
pub const tray_command_quit = contracts.tray_command_quit;
pub const tray_command_open_account_prefix = contracts.tray_command_open_account_prefix;
pub const tray_command_refresh_account_prefix = contracts.tray_command_refresh_account_prefix;
pub const tray_command_switch_failover_prefix = contracts.tray_command_switch_failover_prefix;

pub const Relabel = contracts.Relabel;
pub const MoveAccount = contracts.MoveAccount;
pub const RedeemReset = contracts.RedeemReset;
pub const Command = contracts.Command;
pub const CommandOutcome = contracts.CommandOutcome;
pub const ServiceCapabilities = contracts.ServiceCapabilities;
pub const RenderOptions = contracts.RenderOptions;
pub const ServicePort = contracts.ServicePortFor(ViewState);

pub const ViewState = projection.ViewState;
pub const app_version_text = projection.app_version_text;

pub const selectPrimaryWindow = format.selectPrimaryWindow;
pub const selectCodexPrimaryWindow = format.selectCodexPrimaryWindow;
pub const selectConfiguredCodexPrimaryWindow = format.selectConfiguredCodexPrimaryWindow;
pub const codexPlanClass = format.codexPlanClass;
pub const CodexPlanClass = format.CodexPlanClass;
pub const resetPhrase = format.resetPhrase;
pub const remainingPhrase = format.remainingPhrase;
pub const providerName = format.providerName;
pub const humanizeWindowLabel = format.humanizeWindowLabel;
pub const freshnessText = format.freshnessText;
pub const freshnessPhrase = format.freshnessPhrase;
pub const attemptMessage = format.attemptMessage;
pub const attemptReason = format.attemptReason;
pub const authStateText = format.authStateText;
pub const snapshotStatusText = format.snapshotStatusText;
pub const outcomeIsHonestFailure = format.outcomeIsHonestFailure;
pub const formatLocal = format.formatLocal;
pub const agoPhrase = format.agoPhrase;
pub const shortLocal = format.shortLocal;
pub const mediumLocal = format.mediumLocal;
pub const formatCountdown = format.formatCountdown;
pub const countdownPhrase = format.countdownPhrase;
pub const durationPhrase = format.durationPhrase;

pub fn trayTitle(view: *const ViewState, buffer: []u8) []const u8 {
    return format.trayTitle(view, buffer);
}

pub fn buildTray(view: *const ViewState, out: []TrayItem) usize {
    return format.buildTray(view, out);
}

pub const ResetStage = reset.ResetStage;
pub const ResetBlockReason = reset.ResetBlockReason;
pub const ResetFlow = reset.ResetFlow;
pub const NoticeKind = reset.NoticeKind;
pub const Notice = reset.Notice;
