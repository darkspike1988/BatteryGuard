import Foundation

/// Whitelisted user-selected export. No configuration, messages, paths, tokens or process names.
public struct BGDiagnosticReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let rulesVersion: Int
    public let appVersion: String
    public let daemonVersion: String
    public let generatedAt: Date
    public let battery: BGBatteryMeasurements
    public let system: BGSystemSnapshot?
    public let capacityDays: [BGCapacityDay]
    public let issues: [BGDiagnosticIssue]

    public init(appVersion: String, daemonVersion: String, battery status: BGStatus,
                system: BGSystemSnapshot?, capacityDays: [BGCapacityDay] = [], at now: Date) {
        schemaVersion = 1; rulesVersion = 1; generatedAt = now
        func version(_ text: String) -> String {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard text.count <= 24, (1...4).contains(parts.count),
                  parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return "unknown" }
            return text
        }
        self.appVersion = version(appVersion); self.daemonVersion = version(daemonVersion)
        battery = status.diagnosticMeasurements(at: now)
        if let system, system.isFresh(at: now) {
            self.system = BGSystemSnapshot(sampledAt: system.sampledAt, thermalState: system.thermalState,
                measurements: BGBatteryMeasurements(values: system.measurements.values.map { $0.evaluated(at: now) }),
                modelIdentifier: system.modelIdentifier)
        } else { self.system = nil }
        self.capacityDays = Array(capacityDays.filter { $0.isValid && $0.day >= now.addingTimeInterval(-BGCapacityTrend.retention)
            && $0.lastSampledAt <= now.addingTimeInterval(5) }.sorted { $0.lastSampledAt < $1.lastSampledAt }.suffix(1464))
        issues = BGDiagnosticRules.evaluate(battery: battery, system: self.system, at: now)
    }
}
