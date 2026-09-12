import Foundation

public enum ManagedArtifacts {
    public static func plist(store: RuntimeStore, runtimeID: String, configPath: String,
                             serviceLabel: String = "dev.codexmulti.app.proxy") throws -> Data {
        let app = try store.bundle(runtimeID)
        _ = try store.verifyPayload(in: app)
        let helper = app.appendingPathComponent("Contents/Helpers/codexmulti-maintenance")
        let result = try Commands.run(helper.path, ["render-managed-plist", "--config", configPath])
        guard result.status == 0, let data = result.output.data(using: .utf8),
              var object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              object["ProgramArguments"] as? [String] == RuntimeOperations.arguments(app: app, configPath: configPath) else {
            throw UpdateFailure.invalidManifest
        }
        _ = try LaunchService().target(serviceLabel)
        if serviceLabel != "dev.codexmulti.app.proxy" {
            object["Label"] = serviceLabel
            return try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        }
        return data
    }

    public static func recordHealth(store: RuntimeStore, runtimeID: String, journal: UpdateJournal) throws {
        let app = try store.bundle(runtimeID)
        let helper = app.appendingPathComponent("Contents/Helpers/codexmulti-maintenance")
        guard try Commands.run(helper.path, ["record-managed-health", "--config", journal.configPath]).status == 0 else {
            throw UpdateFailure.recoveryRequired
        }
    }
}
