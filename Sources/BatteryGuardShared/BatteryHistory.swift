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
        guard status.hasBatteryPercent else { return recentSamples(samples, now: now) }
        // Bereinigen, bevor ein alter Zeitstempel nach einer Uhrkorrektur neue Messungen blockiert.
        var result = recentSamples(samples, now: now)
        let age = now.timeIntervalSince(status.updatedAt)
        guard age >= -5, age <= 60 else { return result }
        if let last = result.last, status.updatedAt.timeIntervalSince(last.timestamp) < sampleInterval {
            return result
        }
        result.append(BGHistorySample(status: status))
        return Array(result.suffix(10_081))
    }

    public static func recentSamples(_ samples: [BGHistorySample], now: Date) -> [BGHistorySample] {
        let cutoff = now.addingTimeInterval(-retention)
        let futureLimit = now.addingTimeInterval(5)
        return Array(samples.filter { $0.timestamp >= cutoff && $0.timestamp <= futureLimit }
            .sorted { $0.timestamp < $1.timestamp }.suffix(10_081))
    }

    /// JSON Lines: ein Messpunkt pro Zeile. Neue Messungen werden nur angehängt,
    /// statt jede Minute den ganzen Siebentageverlauf neu zu schreiben.
    public struct DecodedLines: Equatable, Sendable {
        public var samples: [BGHistorySample]
        public var lineCount: Int
        public var invalidLines: Int
        /// Ein abgebrochener letzter Schreibvorgang hinterlässt eine Zeile ohne Zeilenende.
        public var endsCleanly: Bool
    }

    public static func encodeLine(_ sample: BGHistorySample) throws -> Data {
        let encoder = BGJSON.encoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(sample)
        data.append(0x0A)
        return data
    }

    public static func encodeLines(_ samples: [BGHistorySample]) throws -> Data {
        var data = Data()
        for sample in samples { data.append(try encodeLine(sample)) }
        return data
    }

    public static func decodeLines(_ data: Data) -> DecodedLines {
        let decoder = BGJSON.decoder()
        var samples: [BGHistorySample] = []
        var lines = 0
        var invalid = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            lines += 1
            if let sample = try? decoder.decode(BGHistorySample.self, from: Data(line)) {
                samples.append(sample)
            } else {
                invalid += 1
            }
        }
        return DecodedLines(samples: samples, lineCount: lines, invalidLines: invalid,
                            endsCleanly: data.isEmpty || data.last == 0x0A)
    }

    /// True, wenn `next` nur vorne gekürzt und hinten um genau einen Messpunkt verlängert wurde.
    public static func isAppend(_ next: [BGHistorySample], to previous: [BGHistorySample]) -> Bool {
        guard let last = next.last, previous.last.map({ $0.timestamp < last.timestamp }) ?? true else { return false }
        let kept = next.dropLast()
        return kept.count <= previous.count && kept.elementsEqual(previous.suffix(kept.count))
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

    public static func weeklyReport(_ samples: [BGHistorySample], now: Date,
                                    calendar: Calendar = .current) -> BGWeeklyReport {
        let cutoff = now.addingTimeInterval(-7 * 86400)
        let recent = samples.filter { $0.timestamp >= cutoff && $0.timestamp <= now }
        // Kalendertage in der Zeitzone des Benutzers, nicht UTC-Tage.
        let days = Set(recent.filter { $0.percent >= 99 }
            .map { calendar.startOfDay(for: $0.timestamp) })
        return BGWeeklyReport(from: cutoff, to: now, sampleCount: recent.count,
                              summary: summary(recent), fullChargeDays: days.count,
                              highestCycleCount: recent.compactMap(\.cycles).max())
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

public struct BGWeeklyReport: Equatable, Sendable {
    public var from: Date
    public var to: Date
    public var sampleCount: Int
    public var summary: BGHistorySummary
    public var fullChargeDays: Int
    public var highestCycleCount: Int?
    public init(from: Date, to: Date, sampleCount: Int, summary: BGHistorySummary,
                fullChargeDays: Int, highestCycleCount: Int?) {
        self.from = from; self.to = to; self.sampleCount = sampleCount
        self.summary = summary; self.fullChargeDays = fullChargeDays
        self.highestCycleCount = highestCycleCount
    }
}
