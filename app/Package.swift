// swift-tools-version: 6.0
import PackageDescription



let coreObject = "zig/zig-out/lib/cmcore.o"

let package = Package(
    name: "CodexMulti",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "CodexMulti", targets: ["CodexMulti"]),
    ],
    dependencies: [
        .package(path: "../updater"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6"),
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
            dependencies: ["CMCore", "CodexMultiResources",
                           .product(name: "UpdaterKit", package: "updater"),
                           .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CodexMulti",
            linkerSettings: [
                .unsafeFlags([coreObject, "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
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
