// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMultiUpdater",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "UpdaterKit", targets: ["UpdaterKit"]),
        .executable(name: "codexmulti-update-agent", targets: ["UpdateAgent"]),
        .executable(name: "codexmulti-runtime-launcher", targets: ["RuntimeLauncher"]),
    ],
    targets: [
        .target(name: "UpdaterKit", linkerSettings: [.linkedFramework("Security")]),
        .executableTarget(name: "UpdateAgent", dependencies: ["UpdaterKit"]),
        .executableTarget(name: "RuntimeLauncher", dependencies: ["UpdaterKit"]),
        .testTarget(name: "UpdaterKitTests", dependencies: ["UpdaterKit"]),
    ]
)
