import Foundation

/// Hinweis beim Laden eines kalten Akkus. Unter etwa 10 °C steigt beim Laden das Risiko
/// für Lithium-Ablagerungen an der Anode (Waldmann et al. 2014); Apple nennt 10–35 °C als
/// Betriebsumgebung. B-Guard sperrt dabei nichts, macOS regelt das Laden selbst.
public struct BGColdChargingPolicy: Equatable, Sendable {
    public static let warningCelsius = 10.0
    /// Erst nach spürbarer Erwärmung erneut warnen, nicht bei jedem Schwanken um 10 °C.
    public static let releaseCelsius = 12.0

    private var warned = false

    public init() {}

    /// true, wenn jetzt ein Hinweis fällig ist – höchstens einmal pro Kälteepisode.
    public mutating func shouldWarn(temperatureCelsius: Double?, charging: Bool) -> Bool {
        guard let temperatureCelsius, temperatureCelsius.isFinite else { return false }
        if temperatureCelsius >= Self.releaseCelsius {
            warned = false
            return false
        }
        guard charging, temperatureCelsius < Self.warningCelsius, !warned else { return false }
        warned = true
        return true
    }
}

/// Nach einer deutlichen Änderung des Ladelimits verschiebt sich die gemessene Kapazität
/// über Wochen vorübergehend, weil sich Lithium im Anodenüberhang umverteilt
/// (Lewerenz et al. 2018). Die App weist darauf hin, statt eine Alterung oder Erholung
/// vorzutäuschen.
public struct BGLimitChange: Codable, Equatable, Sendable {
    public static let significantStep = 10
    public static let settlingPeriod: TimeInterval = 28 * 86400

    /// Bezugswert; kleine Schritte verschieben ihn nicht, damit sich mehrere kleine
    /// Änderungen zu einer deutlichen summieren.
    public var upperLimit: Int
    public var changedAt: Date?

    public init(upperLimit: Int, changedAt: Date? = nil) {
        self.upperLimit = upperLimit
        self.changedAt = changedAt
    }

    public func observing(upperLimit new: Int, at now: Date) -> BGLimitChange {
        guard abs(new - upperLimit) >= Self.significantStep else { return self }
        return BGLimitChange(upperLimit: new, changedAt: now)
    }

    public func isSettling(at now: Date) -> Bool {
        guard let changedAt else { return false }
        let age = now.timeIntervalSince(changedAt)
        return age >= 0 && age < Self.settlingPeriod
    }
}
