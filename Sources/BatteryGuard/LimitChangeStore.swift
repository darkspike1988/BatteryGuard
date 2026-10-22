import Foundation
import BatteryGuardShared

/// Merkt sich lokal, wann das Ladelimit zuletzt deutlich geändert wurde (siehe BGLimitChange).
enum LimitChangeStore {
    private static let key = "bg.limitChange"

    static func current(_ defaults: UserDefaults = .standard) -> BGLimitChange? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? BGJSON.decoder().decode(BGLimitChange.self, from: data)
    }

    static func observe(upperLimit: Int, at now: Date = Date(), defaults: UserDefaults = .standard) {
        let next = current(defaults)?.observing(upperLimit: upperLimit, at: now) ?? BGLimitChange(upperLimit: upperLimit)
        guard next != current(defaults), let data = try? BGJSON.encoder().encode(next) else { return }
        defaults.set(data, forKey: key)
    }
}
