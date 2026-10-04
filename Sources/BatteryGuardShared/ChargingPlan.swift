import Foundation

public enum BGProfile: String, CaseIterable, Identifiable, Sendable {
    case desk, everyday, mobile
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .desk: "Schreibtisch"
        case .everyday: "Alltag"
        case .mobile: "Unterwegs"
        }
    }
    public var symbol: String {
        switch self {
        case .desk: "desktopcomputer"
        case .everyday: "leaf"
        case .mobile: "bag"
        }
    }
    public var lower: Int { switch self { case .desk: 55; case .everyday: 75; case .mobile: 85 } }
    public var upper: Int { switch self { case .desk: 60; case .everyday: 80; case .mobile: 90 } }
    public func applying(to config: BGConfig) -> BGConfig {
        var c = config
        c.enabled = true
        c.lowerLimit = lower
        c.upperLimit = upper
        c.pauseUntil = nil
        return c.sanitized()
    }
    public func matches(_ c: BGConfig) -> Bool {
        c.enabled && c.lowerLimit == lower && c.upperLimit == upper
    }
}

public extension BGConfig {
    static let travelLeadTime: TimeInterval = 3 * 3600
    static let travelGraceTime: TimeInterval = 3600

    func isPaused(at now: Date) -> Bool {
        pauseUntil.map { $0 > now } ?? false
    }

    func isTravelCharging(at now: Date) -> Bool {
        guard let ready = travelReadyAt else { return false }
        return now >= ready.addingTimeInterval(-Self.travelLeadTime)
            && now < ready.addingTimeInterval(Self.travelGraceTime)
    }

    /// Ein Ablaufdatum wirkt auch ohne laufende Benutzeroberfläche, im Daemon.
    func effective(at now: Date) -> BGConfig {
        var c = sanitized()
        if isPaused(at: now) { c.enabled = false }
        if let deadline = fullChargeUntil, now >= deadline { c.chargeToFullOnce = false }
        if isTravelCharging(at: now) { c.chargeToFullOnce = true }
        if !c.enabled || c.mode == .native || c.mode == .direct { c.chargeToFullOnce = false }
        return c
    }

    /// Abgelaufene Ausnahmen entfernen, ohne die ursprünglichen Limits zu ändern.
    func removingExpiredPlans(at now: Date) -> BGConfig {
        var c = self
        if let deadline = pauseUntil, now >= deadline { c.pauseUntil = nil }
        if let deadline = fullChargeUntil, now >= deadline {
            c.fullChargeUntil = nil
            c.chargeToFullOnce = false
            c.fullChargeRequestID = nil
        }
        if let ready = travelReadyAt, now >= ready.addingTimeInterval(Self.travelGraceTime) {
            c.travelReadyAt = nil
            c.travelRequestID = nil
        }
        return c
    }
}
