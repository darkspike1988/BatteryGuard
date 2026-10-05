import Foundation
import BatteryGuardShared

/// An explicit export schema. Never encode source configuration or status objects.
struct DiagnosticsReport: Codable, Equatable, Sendable {
    let appVersion: String
    let requiredDaemon: String
    let daemonVersion: String
    let macOSVersion: String
    let daemonActive: Bool
    let statusFresh: Bool
    let state: BGChargeState
    let smcKeysDetected: [String]
    let usesNativeDesktopFallback: Bool
    let enabled: Bool
    let mode: BGMode
    let heatEnabled: Bool
    let apiEnabled: Bool
    let controlAllowed: Bool
    let hasPause: Bool
    let hasSpecialPlan: Bool
    let hasTravelPlan: Bool
}

enum DiagnosticsExport {
    private static let allowedSMCKeys: Set<String> = ["CHTE", "CH0B", "CH0C", "CHIE", "CH0J", "CH0I"]

    /// Versions are restricted to short numeric components, so arbitrary source
    /// strings (including daemon errors, tokens or paths) cannot enter the report.
    private static func version(_ value: String) -> String {
        guard !value.isEmpty, value.utf8.count <= 24,
              value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else { return "unknown" }
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.count <= 6 }) else {
            return "unknown"
        }
        return value
    }

    static func build(config: BGConfig, status: BGStatus,
                      appVersion: String = AppVersion.installed,
                      requiredDaemon: String = AppVersion.requiredDaemon,
                      macOSVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                      daemonActive: Bool, apiEnabled: Bool, controlAllowed: Bool,
                      at now: Date = Date()) -> DiagnosticsReport {
        let age = now.timeIntervalSince(status.updatedAt)
        let osComponents = [macOSVersion.majorVersion, macOSVersion.minorVersion, macOSVersion.patchVersion]
        let osVersion = osComponents.allSatisfy({ (0...999999).contains($0) })
            ? osComponents.map(String.init).joined(separator: ".") : "unknown"
        return DiagnosticsReport(
            appVersion: version(appVersion), requiredDaemon: version(requiredDaemon),
            daemonVersion: version(status.daemonVersion), macOSVersion: osVersion,
            daemonActive: daemonActive, statusFresh: age.isFinite && age >= -5 && age <= 60,
            state: status.state,
            smcKeysDetected: Array(Set(status.smcKeysDetected).intersection(allowedSMCKeys)).sorted(),
            usesNativeDesktopFallback: status.usesNativeDesktopFallback,
            enabled: config.enabled, mode: config.mode, heatEnabled: config.heatProtectionCelsius > 0,
            apiEnabled: apiEnabled, controlAllowed: controlAllowed,
            hasPause: config.pauseUntil != nil, hasSpecialPlan: config.specialChargePlan != nil,
            hasTravelPlan: config.travelReadyAt != nil)
    }

    static func data(for report: DiagnosticsReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    /// Only the user-selected destination is written; no implicit data collection.
    static func write(_ report: DiagnosticsReport, to selectedURL: URL) throws {
        try data(for: report).write(to: selectedURL, options: .atomic)
    }
}
