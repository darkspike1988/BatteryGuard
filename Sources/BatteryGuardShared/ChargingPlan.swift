import Foundation

public enum BGProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case desk, everyday, mobile
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .desk: "Schreibtisch"
        case .everyday: "Alltag"
        case .mobile: "Unterwegs"
        }
    }
    public var localizedTitle: String { BGLocalized(title) }
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
        c.specialChargePlan = nil
        return c.sanitized()
    }
    public func matches(_ c: BGConfig) -> Bool {
        c.enabled && c.lowerLimit == lower && c.upperLimit == upper
    }
}

/// Ein Monitorprofil ändert nur die Ladegrenzen, nie Pause, Reise- oder Sonderpläne.
/// Das gespeicherte Profil bleibt unangetastet.
public enum BGDesktopProfileRule {
    public struct Resolution: Equatable, Sendable {
        public var config: BGConfig
        public var active: Bool
    }

    public static func resolve(config: BGConfig, externalDisplay: Bool, now: Date = Date()) -> Resolution {
        guard config.desktopProfileEnabled, externalDisplay, config.enabled,
              config.mode == .auto || config.mode == .pendulum,
              !config.isPaused(at: now), !config.isTravelCharging(at: now),
              config.specialChargePlan == nil, !config.chargeToFullOnce,
              !(config.manualOverrideUntil.map { $0 > now } ?? false) else {
            return Resolution(config: config, active: false)
        }
        let profile = config.desktopProfile ?? .desk
        var updated = config
        updated.lowerLimit = profile.lower
        updated.upperLimit = profile.upper
        return Resolution(config: updated.sanitized(), active: true)
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

        if let plan = c.specialChargePlan {
            if now >= plan.expiresAt || !c.enabled || c.mode == .native || c.mode == .direct {
                c.specialChargePlan = nil
            } else {
                switch plan.kind {
                case .topUp:
                    c.upperLimit = 100
                    c.lowerLimit = 95
                    c.chargeToFullOnce = true
                    c.activeDischargeAboveUpper = false
                case .discharge:
                    c.chargeToFullOnce = false
                    c.upperLimit = plan.targetPercent
                    c.lowerLimit = max(5, plan.targetPercent - 5)
                    c.activeDischargeAboveUpper = true
                case .hold:
                    c.chargeToFullOnce = false
                    c.activeDischargeAboveUpper = false
                    c.upperLimit = plan.targetPercent
                    c.lowerLimit = max(5, plan.targetPercent - 2)
                }
            }
        }
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
        if let plan = c.specialChargePlan, now >= plan.expiresAt {
            c.specialChargePlan = nil
        }
        return c
    }
}
