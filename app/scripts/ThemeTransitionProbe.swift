import AppKit
import SwiftUI
@testable import CodexMulti

@MainActor
final class ThemeProbeHarness {
    static let shared = ThemeProbeHarness()
    let store = CoreStore()
    let fixtureRoot = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputRoot = URL(fileURLWithPath: CommandLine.arguments[2])
    let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "settings"
    var accounts: Bool { mode == "accounts" }
    var sawMain = false
    var sawNativeSelector = false
    var sawPopover = false
    var sawSheet = false
    var failures = 0
    let systemChanges = CommandLine.arguments.contains("--system-changes")
    var originalSystemDark: Bool?
    var options: LaunchOptions {
        LaunchOptions(arguments: ["--show-window", "--no-activate", "--tab=" + (mode == "settings" ? "settings" : "accounts")] + (accounts ? ["--open=rowmenu:0"] : []), environment: [:])
    }
    func publish(_ preference: String) throws {
        let name: String
        switch mode {
        case "accounts": name = "viewstate-proxy-reachable-mapped.json"
        case "add-account": name = "viewstate-add-account-valid.json"
        case "rename": name = "viewstate-rename-open.json"
        default: name = "viewstate-settings-appearance-system.json"
        }
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent(name))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var view = object["view"] as! [String: Any]
        var settings = view["settings"] as! [String: Any]
        settings["appearance"] = preference
        view["settings"] = settings
        object["view"] = view
        let updated = try JSONSerialization.data(withJSONObject: object)
        store.publish(try JSONDecoder().decode(Projection.self, from: updated))
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func appearance(_ value: NSAppearance) -> String { value.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? value.name.rawValue }
    func check(_ actual: NSAppearance, expected: NSAppearance.Name, label: String) {
        if actual.bestMatch(from: [.aqua, .darkAqua]) != expected {
            failures += 1
            print("MISMATCH \(label): expected \(expected.rawValue), got \(appearance(actual))")
        }
    }
    func systemDarkMode(_ value: Bool? = nil) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let command = value.map { "set dark mode to " + ($0 ? "true" : "false") } ?? "get dark mode"
        process.arguments = ["-e", "tell application \"System Events\" to tell appearance preferences to " + command]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "ThemeProbe", code: Int(process.terminationStatus)) }
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return value ?? (text.trimmingCharacters(in: .whitespacesAndNewlines) == "true")
    }
    func run() async {
        do {
            if systemChanges { originalSystemDark = try systemDarkMode() }

            print("SCENE-PROBE started windows=\(NSApp.windows.count)")
            try publish("light")
            try await Task.sleep(for: .milliseconds(200))
            for window in NSApp.windows where window.title == SettingsWindowScene.title { window.orderFrontRegardless() }
            try await Task.sleep(for: .milliseconds(1200))
            let phases: [(String, NSAppearance.Name)] = [("light", .darkAqua), ("dark", .darkAqua), ("light", .darkAqua), ("dark", .aqua), ("system", .aqua), ("system", .darkAqua), ("light", .aqua), ("light", .darkAqua)]
            for (index, phase) in phases.enumerated() {
                let (preference, system) = phase
                if systemChanges {
                    _ = try systemDarkMode(system == .darkAqua)
                    try await Task.sleep(for: .milliseconds(600))
                }
                let inherited = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
                let expectedSystem: NSAppearance.Name = systemChanges ? system : inherited
                let expected: NSAppearance.Name = preference == "system" ? expectedSystem : preference == "dark" ? .darkAqua : .aqua
                try publish(preference)
                try await Task.sleep(for: .milliseconds(400))
                if index == 3, let window = NSApp.windows.first(where: { $0.title == SettingsWindowScene.title }) {
                    window.performClose(nil)
                    window.orderFrontRegardless()
                    try await Task.sleep(for: .milliseconds(300))
                }
                print("SCENE-PROBE phase=\(index)-\(preference) windows=\(NSApp.windows.count)")
                print("APP DEFAULT \(NSApp.appearance?.name.rawValue ?? "nil") EFFECTIVE \(appearance(NSApp.effectiveAppearance))")
                for window in NSApp.windows where window.isVisible {
                    print("SCENE-PROBE phase=\(index)-\(preference) window=\(type(of: window)) title=\(window.title) explicit=\(window.appearance?.name.rawValue ?? "nil") effective=\(appearance(window.effectiveAppearance))")
                    if window.title == SettingsWindowScene.title { sawMain = true }
                    if String(describing: type(of: window)).contains("Popover") { sawPopover = true }
                    if window.sheetParent != nil { sawSheet = true }
                    guard window.title == SettingsWindowScene.title || String(describing: type(of: window)).contains("Popover") || window.sheetParent != nil else { continue }
                    check(window.effectiveAppearance, expected: expected, label: "window-\(index)-\(type(of: window))")
                    guard let content = window.contentView else { continue }
                    let frame = content.superview ?? content
                    for view in descendants(frame) where view is NSPopUpButton || view is NSVisualEffectView || view is WindowChrome.HookView {
                        print("SCENE-PROBE view=\(type(of: view)) explicit=\(view.appearance?.name.rawValue ?? "nil") effective=\(appearance(view.effectiveAppearance))")
                        if view is NSPopUpButton { sawNativeSelector = true }
                        check(view.effectiveAppearance, expected: expected, label: "native-\(index)-\(type(of: view))")
                        var ancestor = view.superview
                        while let parent = ancestor {
                            if let explicit = parent.appearance { print("SCENE-PROBE ancestor=\(type(of: parent)) explicit=\(explicit.name.rawValue)") }
                            ancestor = parent.superview
                        }
                    }
                    frame.layoutSubtreeIfNeeded()
                    frame.displayIfNeeded()
                    let screenshot = outputRoot.appendingPathComponent("\(mode)-\(index)-\(preference)-\(type(of: window)).png")
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), screenshot.path]
                    capture.standardError = Pipe()
                    try capture.run()
                    capture.waitUntilExit()
                    if capture.terminationStatus != 0 { print("CAPTURE unavailable for \(type(of: window))") }

                }
            }
        } catch { failures += 1; print("SCENE-PROBE ERROR \(error)") }
        if !sawMain || (mode == "settings" && !sawNativeSelector) || (accounts && !sawPopover) || ((mode == "add-account" || mode == "rename") && !sawSheet) {
            failures += 1
            print("MISMATCH missing required presentation for \(mode)")
        }
        if let originalSystemDark {
            do { _ = try systemDarkMode(originalSystemDark) }
            catch { failures += 1; print("ERROR restoring system appearance: \(error)") }
        }
        fflush(stdout)
        print("Theme transitions: \(failures == 0 ? "PASS" : "FAIL") (\(failures) mismatches)")
        exit(failures == 0 ? 0 : 1)
    }
}

@MainActor
final class ThemeProbeDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        print("SCENE-PROBE will launch")
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = nil
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("SCENE-PROBE did launch")
        Task { await ThemeProbeHarness.shared.run() }
    }
}

struct ThemeProbeOpener: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: "circle")
            .onAppear { openWindow(id: SettingsWindowScene.id) }
    }
}

@main
struct ThemeProbeApp: App {
    @NSApplicationDelegateAdaptor(ThemeProbeDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra { Text("Theme probe") } label: { ThemeProbeOpener() }
        SettingsWindowScene(store: ThemeProbeHarness.shared.store, options: ThemeProbeHarness.shared.options, submit: { _ in })
    }
}

