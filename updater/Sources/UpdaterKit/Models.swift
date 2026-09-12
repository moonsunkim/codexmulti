import Foundation

public enum UpdateFailure: String, Error, Codable, Sendable {
    case invalidPath = "invalid_path"
    case unsafePermissions = "unsafe_permissions"
    case invalidSignature = "invalid_signature"
    case invalidManifest = "invalid_manifest"
    case payloadMismatch = "payload_mismatch"
    case incompatibleVersion = "incompatible_version"
    case updateBusy = "update_busy"
    case migrationRequired = "migration_required"
    case serviceOwnershipUnknown = "service_ownership_unknown"
    case proxyBusy = "proxy_busy"
    case proxyUnreachable = "proxy_unreachable"
    case identityMismatch = "identity_mismatch"
    case processStillRunning = "process_still_running"
    case candidateFailed = "candidate_failed"
    case activationUnconfirmed = "activation_unconfirmed"
    case recoveryRequired = "recovery_required"
    case appRecoveryRequired = "app_recovery_required"
    case invalidTransaction = "invalid_transaction"
    case installStillArmed = "install_still_armed"
    case insufficientSpace = "insufficient_space"
    case invalidCommand = "invalid_command"
    case removalNotPrepared = "removal_not_prepared"
    case runtimeDeferred = "runtime_deferred"
}

public enum UpdatePhase: String, Codable, Sendable, CaseIterable {
    case preparingApp = "PREPARING_APP"
    case appPrepared = "APP_PREPARED"
    case installingApp = "INSTALLING_APP"
    case awaitingGUI = "AWAITING_GUI"
    case waitingIdle = "WAITING_IDLE"
    case quiescent = "QUIESCENT"
    case stopCommitted = "STOP_COMMITTED"
    case candidateGated = "CANDIDATE_GATED"
    case activationCommitted = "ACTIVATION_COMMITTED"
    case verifying = "VERIFYING"
    case rollingBack = "ROLLING_BACK"
    case complete = "COMPLETE"
    case cancelled = "CANCELLED"
    case rolledBack = "ROLLED_BACK"
    case recoveryRequired = "RECOVERY_REQUIRED"
    case appRecoveryRequired = "APP_RECOVERY_REQUIRED"

    public var terminal: Bool {
        [.complete, .cancelled, .rolledBack, .recoveryRequired, .appRecoveryRequired].contains(self)
    }

    public var permitsOldRuntime: Bool {
        [.preparingApp, .appPrepared, .installingApp, .awaitingGUI, .waitingIdle,
         .complete, .cancelled, .rolledBack, .appRecoveryRequired].contains(self)
    }
}

public struct RuntimeManifest: Codable, Equatable, Sendable {
    public var schema: Int
    public var runtimeID: String
    public var appBuild: String
    public var architecture: String
    public var proxyTreeSHA256: String
    public var nodeContentSHA256: String
    public var nodeSignedSHA256: String
    public var launcherContentSHA256: String
    public var launcherSignedSHA256: String
    public var agentContentSHA256: String
    public var agentSignedSHA256: String
    public var activationRevision: Int
    public var updateProtocol: Int
    public var configSchema: Int
    public var stateSchema: Int
    public var minimumGUIProtocol: Int
    public var maximumGUIProtocol: Int
    public var proxyFiles: [String: String]

    enum CodingKeys: String, CodingKey {
        case schema, architecture
        case runtimeID = "runtime_id", appBuild = "app_build"
        case proxyTreeSHA256 = "proxy_tree_sha256", proxyFiles = "proxy_files"
        case nodeContentSHA256 = "node_content_sha256", nodeSignedSHA256 = "node_signed_sha256"
        case launcherContentSHA256 = "launcher_content_sha256", launcherSignedSHA256 = "launcher_signed_sha256"
        case agentContentSHA256 = "agent_content_sha256", agentSignedSHA256 = "agent_signed_sha256"
        case activationRevision = "activation_revision", updateProtocol = "update_protocol"
        case configSchema = "config_schema", stateSchema = "state_schema"
        case minimumGUIProtocol = "minimum_gui_protocol", maximumGUIProtocol = "maximum_gui_protocol"
    }

    public func validate() throws {
        guard schema == 1, architecture == "arm64", updateProtocol == 1,
              configSchema == 1, stateSchema == 1, minimumGUIProtocol <= 1,
              maximumGUIProtocol >= 1, activationRevision >= 0,
              !appBuild.isEmpty, appBuild.count < 80, !proxyFiles.isEmpty,
              [runtimeID, proxyTreeSHA256, nodeContentSHA256, nodeSignedSHA256,
               launcherContentSHA256, launcherSignedSHA256, agentContentSHA256, agentSignedSHA256].allSatisfy(Disk.isDigest) else {
            throw UpdateFailure.invalidManifest
        }
        let identity = "codexmulti-runtime-v1\n\(architecture)\n\(proxyTreeSHA256)\n\(nodeContentSHA256)\n\(launcherContentSHA256)\n\(agentContentSHA256)\n\(activationRevision)\n"
        guard Disk.digest(Data(identity.utf8)) == runtimeID else { throw UpdateFailure.invalidManifest }
    }
}

public struct ActiveRuntime: Codable, Equatable, Sendable {
    public var schema = 1
    public var runtimeID: String
    public var generation: Int
    public var transactionID: String?
    public var epoch: Int
    enum CodingKeys: String, CodingKey {
        case schema, generation, epoch
        case runtimeID = "runtime_id", transactionID = "transaction_id"
    }
    public init(runtimeID: String, generation: Int, transactionID: String? = nil, epoch: Int = 1) {
        self.runtimeID = runtimeID
        self.generation = generation
        self.transactionID = transactionID
        self.epoch = epoch
    }
}

public struct UpdatePointer: Codable, Sendable {
    public var schema = 1
    public var transactionID: String
    enum CodingKeys: String, CodingKey { case schema; case transactionID = "transaction_id" }
    public init(transactionID: String) { self.transactionID = transactionID }
}

public struct DeferredRuntime: Codable, Sendable {
    public var schema = 1
    public var appBuild: String
    public var runtimeID: String
    enum CodingKeys: String, CodingKey {
        case schema
        case appBuild = "app_build", runtimeID = "runtime_id"
    }
    public init(appBuild: String, runtimeID: String) { self.appBuild = appBuild; self.runtimeID = runtimeID }
}

public struct UpdateJournal: Codable, Sendable {
    public var schema = 1
    public var transactionID: String
    public var epoch = 1
    public var phase: UpdatePhase
    public var appPath: String
    public var previousAppBuild: String
    public var targetAppBuild: String
    public var oldRuntimeID: String
    public var targetRuntimeID: String
    public var configPath: String
    public var configRevision: String
    public var desiredEnabled: Bool
    public var previousGeneration: Int
    public var activationGeneration: Int
    public var expectedBootID: String?
    public var candidateBootID: String?
    public var oldPID: Int32?
    public var oldProcessStart: String?
    public var oldPlistSHA256: String?
    public var candidatePlistSHA256: String?
    public var serviceLabel: String
    public var installArmed = false
    public var guiReady = false
    public var cancellationRequested = false
    public var rollbackAttempted = false
    public var failure: UpdateFailure?
    public var startedAt: Date
    public var updatedAt: Date
    public var helperSHA256: String?
    public var appManifestSHA256: String?
    public var kind: String

    enum CodingKeys: String, CodingKey {
        case schema, epoch, phase, failure, kind
        case transactionID = "transaction_id", appPath = "app_path"
        case previousAppBuild = "previous_app_build", targetAppBuild = "target_app_build"
        case oldRuntimeID = "old_runtime_id", targetRuntimeID = "target_runtime_id"
        case configPath = "config_path", configRevision = "config_revision", desiredEnabled = "desired_enabled"
        case previousGeneration = "previous_generation", activationGeneration = "activation_generation"
        case expectedBootID = "expected_boot_id", candidateBootID = "candidate_boot_id"
        case oldPID = "old_pid", oldProcessStart = "old_process_start"
        case oldPlistSHA256 = "old_plist_sha256", candidatePlistSHA256 = "candidate_plist_sha256"
        case serviceLabel = "service_label", installArmed = "install_armed", guiReady = "gui_ready"
        case cancellationRequested = "cancellation_requested", rollbackAttempted = "rollback_attempted"
        case startedAt = "started_at", updatedAt = "updated_at"
        case helperSHA256 = "helper_sha256", appManifestSHA256 = "app_manifest_sha256"
    }

    public init(transactionID: String = UUID().uuidString.lowercased(), phase: UpdatePhase,
                appPath: String, previousAppBuild: String, targetAppBuild: String,
                oldRuntimeID: String, targetRuntimeID: String, configPath: String,
                configRevision: String, desiredEnabled: Bool, previousGeneration: Int,
                serviceLabel: String = "dev.codexmulti.app.proxy", kind: String = "app") {
        self.transactionID = transactionID; self.phase = phase; self.appPath = appPath
        self.previousAppBuild = previousAppBuild; self.targetAppBuild = targetAppBuild
        self.oldRuntimeID = oldRuntimeID; self.targetRuntimeID = targetRuntimeID
        self.configPath = configPath; self.configRevision = configRevision
        self.desiredEnabled = desiredEnabled; self.previousGeneration = previousGeneration
        self.activationGeneration = previousGeneration + 1; self.serviceLabel = serviceLabel
        self.kind = kind; self.startedAt = Date(); self.updatedAt = Date()
    }
}

public struct ProxyHealth: Codable, Equatable, Sendable {
    public var updateProtocol: Int
    public var managed: Bool
    public var runtimeID: String?
    public var bootID: String
    public var generation: Int
    public var gate: String
    public var configRevision: String?
    public var configPath: String?
    public var work: [String: Int]
    public var workTotal: Int
    public var payloadVerified: Bool
    public var lease: String?
    public var leaseRemainingMS: Double?

    enum CodingKeys: String, CodingKey {
        case managed, generation, gate, work, lease
        case updateProtocol = "update_protocol", runtimeID = "runtime_id", bootID = "boot_id"
        case configRevision = "config_revision", configPath = "config_path"
        case workTotal = "work_total", payloadVerified = "payload_verified"
        case leaseRemainingMS = "lease_remaining_ms"
    }
}
