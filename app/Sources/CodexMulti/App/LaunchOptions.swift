import Foundation




































struct LaunchOptions: Equatable, Sendable {


    enum OpenTarget: Equatable, Sendable {
        case rowMenu(row: UInt32)
        case proxyRowMenu(row: UInt32)
        case dialog(DialogTarget)



        init?(flag text: String) {
            if text.hasPrefix("rowmenu:"), let row = UInt32(text.dropFirst("rowmenu:".count)) {
                self = .rowMenu(row: row)
            } else if text.hasPrefix("failovermenu:"), let row = UInt32(text.dropFirst("failovermenu:".count)) {
                self = .proxyRowMenu(row: row)
            } else if let dialog = DialogTarget(flag: text) {
                self = .dialog(dialog)
            } else {
                return nil
            }
        }
    }

    static let headlessEnvironmentKey = "CODEXMULTI_TEST_HEADLESS"
    static let visualQAEnvironmentKey = "CODEXMULTI_VISUAL_QA_SHOW_SETTINGS"
    static let captureVersionEnvironmentKey = "CODEXMULTI_CAPTURE_VERSION_TEXT"

    var fixturePath: String?
    var capturePath: String?
    var captureVersionText: String?
    var showWindow = false
    var setAppearanceOnLaunch: Appearance?
    var frame: CGRect?
    var noActivate = false
    var noStatusItem = false
    var tab: SettingsTab?
    var expand: UInt32?
    var open: OpenTarget?
    var keychainProbe = false
    var headless = false
    var visualQAShowSettings = false

    init(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) {
        func value(after flag: String) -> String? {
            if let joined = arguments.first(where: { $0.hasPrefix(flag + "=") }) {
                return String(joined.dropFirst(flag.count + 1))
            }
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        fixturePath = value(after: "--fixture")
        capturePath = value(after: "--capture")
        captureVersionText = environment[Self.captureVersionEnvironmentKey]


        showWindow = capturePath == nil && arguments.contains("--show-window")


        setAppearanceOnLaunch = value(after: "--set-appearance").flatMap(Appearance.init(rawValue:))
        noActivate = capturePath != nil || arguments.contains("--no-activate")
        noStatusItem = capturePath != nil || arguments.contains("--no-status-item")
        keychainProbe = arguments.contains("--keychain-probe")
        if let text = value(after: "--frame") {
            let parts = text.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                frame = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
        if let text = value(after: "--tab") {
            tab = text == "settings" ? .failover : SettingsTab(rawValue: text)
        }
        if let text = value(after: "--expand"), let row = UInt32(text) {
            expand = row
        }
        if let text = value(after: "--open") {
            open = OpenTarget(flag: text)
        }
        headless = capturePath != nil || environment[Self.headlessEnvironmentKey] == "1" || (noStatusItem && noActivate)
        visualQAShowSettings = environment[Self.visualQAEnvironmentKey] == "1"
    }
}
