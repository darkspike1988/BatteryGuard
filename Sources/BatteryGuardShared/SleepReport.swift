import Foundation

/// Ein Eintrag aus `pmset -g log`. Das Format ist nicht dokumentiert und kann sich ändern;
/// unbekannte Zeilen werden übersprungen, statt Fehler zu melden.
public struct BGPowerEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case sleep, wake, darkWake }

    public var date: Date
    public var kind: Kind
    /// Text nach „due to“, z. B. „EC.ARPT/Maintenance“.
    public var reason: String?
    public var chargePercent: Int?
    public var onAC: Bool?

    public init(date: Date, kind: Kind, reason: String? = nil, chargePercent: Int? = nil, onAC: Bool? = nil) {
        self.date = date
        self.kind = kind
        self.reason = reason
        self.chargePercent = chargePercent
        self.onAC = onAC
    }
}

public enum BGPowerLogParser {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    public static func events(from log: String) -> [BGPowerEvent] {
        var result: [BGPowerEvent] = []
        for line in log.split(separator: "\n", omittingEmptySubsequences: true) {
            if let event = event(from: line) { result.append(event) }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func event(from line: Substring) -> BGPowerEvent? {
        // „2026-10-22 23:14:05 +0200 Sleep               \tEntering Sleep state …“
        guard line.count > 26 else { return nil }
        let dateEnd = line.index(line.startIndex, offsetBy: 25)
        guard let date = formatter.date(from: String(line[..<dateEnd])) else { return nil }
        let rest = line[dateEnd...].drop { $0 == " " }
        let kindText = rest.prefix { !$0.isWhitespace }
        let kind: BGPowerEvent.Kind
        switch kindText {
        case "Sleep": kind = .sleep
        case "Wake": kind = .wake
        case "DarkWake": kind = .darkWake
        default: return nil
        }
        let detail = rest.dropFirst(kindText.count)
        return BGPowerEvent(date: date, kind: kind, reason: reason(in: detail),
                            chargePercent: charge(in: detail), onAC: power(in: detail))
    }

    private static func reason(in detail: Substring) -> String? {
        guard let start = detail.range(of: "due to ") else { return nil }
        var text = detail[start.upperBound...]
        for terminator in [" Using ", ":TCPKeepAlive", ":", " ("] {
            if let end = text.range(of: terminator) { text = text[..<end.lowerBound] }
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " '\"\t"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func charge(in detail: Substring) -> Int? {
        guard let start = detail.range(of: "Charge:") else { return nil }
        let digits = detail[start.upperBound...].prefix { $0.isNumber }
        return Int(digits).flatMap { (0...100).contains($0) ? $0 : nil }
    }

    private static func power(in detail: Substring) -> Bool? {
        guard let start = detail.range(of: "Using ") else { return nil }
        let word = detail[start.upperBound...].prefix { $0.isLetter }.lowercased()
        switch word {
        case "ac": return true
        case "batt": return false
        default: return nil
        }
    }
}

/// Eine Schlafphase auf Akku, vom Einschlafen bis zum vollen Aufwachen.
public struct BGSleepSession: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var startPercent: Int
    public var endPercent: Int
    public var darkWakes: Int
    /// Gründe für dunkles Aufwachen mit Häufigkeit, häufigster zuerst.
    public var darkWakeReasons: [BGReasonCount]
    public var wakeReason: String?

    public init(start: Date, end: Date, startPercent: Int, endPercent: Int, darkWakes: Int,
                darkWakeReasons: [BGReasonCount], wakeReason: String?) {
        self.start = start
        self.end = end
        self.startPercent = startPercent
        self.endPercent = endPercent
        self.darkWakes = darkWakes
        self.darkWakeReasons = darkWakeReasons
        self.wakeReason = wakeReason
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var drainPoints: Int { max(0, startPercent - endPercent) }
    public var drainPerHour: Double {
        duration > 0 ? Double(drainPoints) / (duration / 3600) : 0
    }
}

public struct BGReasonCount: Codable, Equatable, Sendable {
    public var reason: String
    public var count: Int

    public init(reason: String, count: Int) {
        self.reason = reason
        self.count = count
    }
}

public struct BGSleepReport: Equatable, Sendable {
    public var session: BGSleepSession
    /// Median der früheren Schlafphasen in Prozentpunkten pro Stunde.
    public var baselinePerHour: Double?
    public var unusual: Bool
}

public enum BGSleepAnalysis {
    /// Kürzere Phasen sind zu ungenau für eine Rate (Ladestand in ganzen Prozent).
    public static let minimumDuration: TimeInterval = 30 * 60
    public static let minimumUnusualDrain = 4
    public static let absoluteUnusualRate = 1.0
    public static let baselineFactor = 2.5
    public static let minimumBaselineSessions = 3

    public static func sessions(from events: [BGPowerEvent]) -> [BGSleepSession] {
        var result: [BGSleepSession] = []
        var open: (start: Date, percent: Int)?
        var darkWakes = 0
        var reasons: [String: Int] = [:]
        var lastPercent: Int?
        var pluggedDuringSleep = false

        for event in events {
            switch event.kind {
            case .sleep:
                // Ein zweites „Sleep“ ohne Wake (z. B. nach DarkWake) setzt die Phase fort.
                if open == nil {
                    darkWakes = 0
                    reasons = [:]
                    pluggedDuringSleep = event.onAC == true
                    if let percent = event.chargePercent { open = (event.date, percent) }
                } else if event.onAC == true {
                    pluggedDuringSleep = true
                }
                if let percent = event.chargePercent { lastPercent = percent }
            case .darkWake:
                guard open != nil else { continue }
                darkWakes += 1
                if let reason = event.reason { reasons[reason, default: 0] += 1 }
                if event.onAC == true { pluggedDuringSleep = true }
                if let percent = event.chargePercent { lastPercent = percent }
            case .wake:
                defer { open = nil }
                guard let start = open else { continue }
                if event.onAC == true { pluggedDuringSleep = true }
                guard !pluggedDuringSleep, let endPercent = event.chargePercent ?? lastPercent,
                      event.date.timeIntervalSince(start.start) >= minimumDuration else { continue }
                let sorted = reasons.map { BGReasonCount(reason: $0.key, count: $0.value) }
                    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
                result.append(BGSleepSession(start: start.start, end: event.date,
                                             startPercent: start.percent, endPercent: endPercent,
                                             darkWakes: darkWakes, darkWakeReasons: sorted,
                                             wakeReason: event.reason))
            }
        }
        return result
    }

    /// Bericht für die letzte Schlafphase im Vergleich zu den vorherigen.
    public static func latestReport(from sessions: [BGSleepSession]) -> BGSleepReport? {
        guard let latest = sessions.last else { return nil }
        let earlier = sessions.dropLast().suffix(20).map(\.drainPerHour).sorted()
        let baseline: Double? = earlier.count >= minimumBaselineSessions ? median(earlier) : nil
        let threshold = max(absoluteUnusualRate, (baseline ?? 0) * baselineFactor)
        let unusual = latest.drainPoints >= minimumUnusualDrain && latest.drainPerHour >= threshold
        return BGSleepReport(session: latest, baselinePerHour: baseline, unusual: unusual)
    }

    private static func median(_ sorted: [Double]) -> Double {
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// Aktive Energie-Assertions, die den Ruhezustand verhindern (IOPMCopyAssertionsByProcess).
public struct BGSleepBlocker: Equatable, Sendable, Identifiable {
    public static let preventingTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion",
    ]

    public var pid: Int32
    public var process: String
    public var type: String
    public var name: String

    public var id: String { "\(pid)-\(type)-\(name)" }

    public init(pid: Int32, process: String, type: String, name: String) {
        self.pid = pid
        self.process = process
        self.type = type
        self.name = name
    }

    /// Nur Assertions, die den Schlaf verhindern; doppelte je Prozess und Name zusammengefasst.
    public static func relevant(_ all: [BGSleepBlocker]) -> [BGSleepBlocker] {
        var seen = Set<String>()
        return all.filter { preventingTypes.contains($0.type) }
            .filter { seen.insert("\($0.pid)-\($0.name)").inserted }
            .sorted { $0.process.localizedCaseInsensitiveCompare($1.process) == .orderedAscending }
    }
}
