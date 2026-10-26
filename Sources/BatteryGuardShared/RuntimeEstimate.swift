import Foundation

/// Restlaufzeit aus dem durchschnittlichen Entladefluss eines Zeitfensters statt aus dem Momentanwert.
public enum BGRuntimeEstimate {
    public static let windows = [5, 15, 60]
    public static let minimumSamples = 5

    /// Minuten bis leer; nil am Netzteil, bei zu wenigen Akku-Messpunkten oder fehlender Kapazität.
    public static func minutesRemaining(samples: [BGHistorySample], windowMinutes: Int, now: Date,
                                        percent: Int, maxCapacityMah: Int?, voltageMillivolts: Double?) -> Int? {
        guard let capacity = maxCapacityMah, capacity > 0, let voltage = voltageMillivolts, voltage > 0,
              (1...100).contains(percent) else { return nil }
        let start = now.addingTimeInterval(-Double(windowMinutes) * 60)
        let discharge = samples.filter { $0.timestamp >= start && $0.timestamp <= now && !$0.pluggedIn }
            .compactMap(\.watts).filter { $0.isFinite && $0 < -0.1 }
        guard discharge.count >= minimumSamples else { return nil }
        let averageWatts = -discharge.reduce(0, +) / Double(discharge.count)
        let remainingWattHours = Double(capacity) * Double(percent) / 100 * voltage / 1_000_000
        let minutes = remainingWattHours / averageWatts * 60
        guard minutes.isFinite, minutes > 0, minutes < 100 * 60 else { return nil }
        return Int(minutes.rounded())
    }
}
