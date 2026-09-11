import AppKit




enum SingleInstanceGuard {
    @MainActor
    static func otherInstance(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> NSRunningApplication? {
        guard let bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != me }
    }
}
