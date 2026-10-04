// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryGuard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BatteryGuard", targets: ["BatteryGuard"]),
        .executable(name: "batteryguardd", targets: ["batteryguardd"]),
    ],
    targets: [
        // Gemeinsame Typen (Config/Status-Protokoll zwischen App und Daemon)
        .target(name: "BatteryGuardShared"),
        // Root-Daemon: Akku überwachen + SMC schreiben
        .executableTarget(
            name: "batteryguardd",
            dependencies: ["BatteryGuardShared"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Menüleisten-App (SwiftUI, MenuBarExtra)
        .executableTarget(
            name: "BatteryGuard",
            dependencies: ["BatteryGuardShared"]
        ),
        .testTarget(name: "BatteryGuardTests", dependencies: ["batteryguardd", "BatteryGuardShared", "BatteryGuard"]),
    ]
)
