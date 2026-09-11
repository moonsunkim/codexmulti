const domain = @import("domain.zig");
const keychain = @import("keychain.zig");
const protocol = @import("oauth_protocol.zig");

const RefreshPayload = protocol.RefreshPayload;
const public_code_store_corrupt = protocol.public_code_store_corrupt;
const refreshErrorFromStore = protocol.refreshErrorFromStore;

pub const RotationOutcome = enum {
    no_rotation,

    rotated,

    rotated_staging_not_cleared,

    staging_failed_old_credential_retained,

    promotion_failed_staged_recoverable,

    pub fn refreshCredentialAdvanced(self: RotationOutcome) bool {
        return switch (self) {
            .rotated, .rotated_staging_not_cleared => true,
            else => false,
        };
    }

    pub fn oldRefreshCredentialRetained(self: RotationOutcome) bool {
        return switch (self) {
            .no_rotation, .staging_failed_old_credential_retained, .promotion_failed_staged_recoverable => true,
            else => false,
        };
    }

    pub fn needsRecoverySweep(self: RotationOutcome) bool {
        return switch (self) {
            .rotated_staging_not_cleared, .promotion_failed_staged_recoverable => true,
            else => false,
        };
    }
};

pub const RotationResult = struct {
    outcome: RotationOutcome,

    failure: ?domain.RefreshError = null,

    pub fn ok(self: RotationResult) bool {
        return self.failure == null;
    }
};

pub fn rotateRefreshCredential(
    store: keychain.CredentialStore,
    account: *const keychain.AccountKey,
    rotated: ?*const keychain.Credential,
) RotationResult {
    const replacement = rotated orelse return .{ .outcome = .no_rotation };
    if (replacement.isEmpty()) return .{ .outcome = .no_rotation };

    store.save(account, .staged_refresh_token, replacement) catch |err| {
        return .{ .outcome = .staging_failed_old_credential_retained, .failure = refreshErrorFromStore(err) };
    };

    var staged: keychain.Credential = .empty;
    defer staged.wipe();
    store.load(account, .staged_refresh_token, &staged) catch |err| {
        store.remove(account, .staged_refresh_token) catch {};
        return .{ .outcome = .staging_failed_old_credential_retained, .failure = refreshErrorFromStore(err) };
    };
    if (!staged.eql(replacement)) {
        store.remove(account, .staged_refresh_token) catch {};
        return .{
            .outcome = .staging_failed_old_credential_retained,
            .failure = .{ .kind = .persistence, .public_code = public_code_store_corrupt, .retryable = false },
        };
    }

    store.save(account, .refresh_token, replacement) catch |err| {
        return .{ .outcome = .promotion_failed_staged_recoverable, .failure = refreshErrorFromStore(err) };
    };

    store.remove(account, .staged_refresh_token) catch {
        return .{ .outcome = .rotated_staging_not_cleared };
    };
    return .{ .outcome = .rotated };
}

pub const RecoveryOutcome = enum {
    nothing_staged,
    promoted_staged,
    promoted_staged_not_cleared,
    promotion_failed_staged_retained,
    staging_unreadable,
};

pub const RecoveryResult = struct {
    outcome: RecoveryOutcome,
    failure: ?domain.RefreshError = null,
};

pub fn recoverStagedRotation(
    store: keychain.CredentialStore,
    account: *const keychain.AccountKey,
) RecoveryResult {
    const staged_present = store.contains(account, .staged_refresh_token) catch |err| {
        return .{ .outcome = .staging_unreadable, .failure = refreshErrorFromStore(err) };
    };
    if (!staged_present) return .{ .outcome = .nothing_staged };

    var staged: keychain.Credential = .empty;
    defer staged.wipe();
    store.load(account, .staged_refresh_token, &staged) catch |err| {
        return .{ .outcome = .staging_unreadable, .failure = refreshErrorFromStore(err) };
    };
    if (staged.isEmpty()) {
        store.remove(account, .staged_refresh_token) catch {};
        return .{ .outcome = .nothing_staged };
    }

    store.save(account, .refresh_token, &staged) catch |err| {
        return .{ .outcome = .promotion_failed_staged_retained, .failure = refreshErrorFromStore(err) };
    };
    store.remove(account, .staged_refresh_token) catch {
        return .{ .outcome = .promoted_staged_not_cleared };
    };
    return .{ .outcome = .promoted_staged };
}

pub const ApplyResult = struct {
    rotation: RotationResult,
    access_stored: bool = false,

    failure: ?domain.RefreshError = null,
};

pub fn applyRefreshPayload(
    store: keychain.CredentialStore,
    account: *const keychain.AccountKey,
    payload: *const RefreshPayload,
) ApplyResult {
    const rotation = rotateRefreshCredential(store, account, payload.rotatedRefresh());
    var result: ApplyResult = .{ .rotation = rotation, .failure = rotation.failure };
    store.save(account, .access_token, &payload.access) catch |err| {
        if (result.failure == null) result.failure = refreshErrorFromStore(err);
        return result;
    };
    result.access_stored = true;
    return result;
}
