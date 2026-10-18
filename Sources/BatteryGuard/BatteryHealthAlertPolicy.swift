import Foundation

/// Entscheidet, wann ein Wartungshinweis wegen niedriger Akkukapazität erscheint.
/// Die Kapazität ist eine Schätzung aus Design- und Maximalkapazität, kein Hardwaretest.
enum BatteryHealthAlertPolicy {
    static let validRange = 50...95
    static let repeatInterval: TimeInterval = 30 * 86400

    static func clampThreshold(_ value: Int) -> Int {
        min(max(value, validRange.lowerBound), validRange.upperBound)
    }

    static func threshold(from preferences: UserDefaults) -> Int {
        clampThreshold(preferences.object(forKey: "bg.healthThreshold") as? Int ?? 80)
    }

    static func shouldNotify(healthPercent: Int?, threshold: Int, lastSent: Date?, now: Date) -> Bool {
        guard let healthPercent, healthPercent > 0, healthPercent <= 100 else { return false }
        guard healthPercent < clampThreshold(threshold) else { return false }
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= repeatInterval
    }
}
