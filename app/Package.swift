// swift-tools-version: 6.0
import PackageDescription



let coreObject = "zig/zig-out/lib/cmcore.o"

let package = Package(
    name: "CodexMulti",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "CodexMulti", targets: ["CodexMulti"]),
    ],
    targets: [
        .systemLibrary(name: "CMCore", path: "Sources/CMCore"),
        .target(
            name: "CodexMultiResources",
            path: "Resources",
            exclude: ["Info.plist", "node.entitlements", "AppIcon.icns"],
            sources: ["CodexMultiResourceBundle.swift"],
            resources: [
                .copy("TrayIcon.png"),
                .copy("TrayIcon@2x.png"),
                .copy("TrayIcon@3x.png"),
            ]
        ),
        .executableTarget(
            name: "CodexMulti",
            dependencies: ["CMCore", "CodexMultiResources"],
            path: "Sources/CodexMulti",
            linkerSettings: [
                .unsafeFlags([coreObject]),
                .linkedFramework("Security"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "CodexMultiTests",
            dependencies: ["CodexMulti"],
            path: "Tests/CodexMultiTests"
        ),
    ]
)
