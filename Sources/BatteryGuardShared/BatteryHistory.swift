import Foundation

public struct BGHistorySample: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let percent: Int
    public let temperature: Double?
    public let watts: Double?
    public let health: Int?
    public let cycles: Int?
    public let state: BGChargeState
    public let pluggedIn: Bool

    public init(status: BGStatus) {
        timestamp = status.updatedAt
        percent = min(max(status.percent, 0), 100)
        temperature = status.temperatureCelsius
        watts = status.watts
        health = status.healthPercent
        cycles = status.cycleCount
        state = status.state
        pluggedIn = status.pluggedIn
    }
}

public enum BGHistory {
    public static let retention: TimeInterval = 7 * 24 * 3600
    public static let sampleInterval: TimeInterval = 60

    public static func recording(_ status: BGStatus, in samples: [BGHistorySample], now: Date) -> [BGHistorySample] {
        // Keine veralteten, zukünftigen oder doppelten Messungen aufzeichnen.
        let age = now.timeIntervalSince(status.updatedAt)
        guard age >= -5, age <= 60 else { return samples }
        if let last = samples.last, status.updatedAt.timeIntervalSince(last.timestamp) < sampleInterval {
            return samples
        }
        let cutoff = now.addingTimeInterval(-retention)
        var result = samples.filter { $0.timestamp >= cutoff }
        result.append(BGHistorySample(status: status))
        return Array(result.suffix(10_081))
    }

    public static func csv(_ samples: [BGHistorySample]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["timestamp,percent,temperature_celsius,watts,health_percent,cycles,state,plugged_in"]
        rows += samples.map { s in
            [formatter.string(from: s.timestamp), String(s.percent),
             s.temperature.map { String($0) } ?? "", s.watts.map { String($0) } ?? "",
             s.health.map { String($0) } ?? "", s.cycles.map { String($0) } ?? "",
             s.state.rawValue, String(s.pluggedIn)].joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Zeitgewichtete Auswertung. Lücken über zwei Minuten werden nicht überbrückt.
    public static func summary(_ samples: [BGHistorySample]) -> BGHistorySummary {
        var result = BGHistorySummary()
        for (a, b) in zip(samples, samples.dropFirst()) {
            let duration = b.timestamp.timeIntervalSince(a.timestamp)
            guard duration > 0, duration <= 120 else { continue }
            result.observedSeconds += duration
            if a.percent >= 90 { result.highChargeSeconds += duration }
            if a.state == .holding { result.heldSeconds += duration }
            if let temp = a.temperature, temp >= 40 { result.hotSeconds += duration }
        }
        result.peakTemperature = samples.compactMap(\.temperature).max()
        return result
    }
}

public struct BGHistorySummary: Equatable, Sendable {
    public var observedSeconds: TimeInterval = 0
    public var highChargeSeconds: TimeInterval = 0
    public var heldSeconds: TimeInterval = 0
    public var hotSeconds: TimeInterval = 0
    public var peakTemperature: Double? = nil
    public init() {}
}
