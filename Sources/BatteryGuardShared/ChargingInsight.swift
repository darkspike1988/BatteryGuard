import Foundation

/// Zustand eines SMC-Steuerschlüssels, wie ihn der Dienst beim Start ermittelt.
/// Ab der Firmware von macOS 27 sperrt Apple die Ladesperre-Schlüssel hinter einem privaten
/// Entitlement; sie erscheinen dann als Platzhalter der Größe null oder liefern selbst für
/// root `kIOReturnNotPrivileged`. Deshalb wird nach Fähigkeit statt nach macOS-Version verzweigt.
public enum BGSMCKeyState: String, Codable, Sendable {
    case absent
    /// Schlüssel existiert, hat aber Größe null.
    case placeholder
    /// Schreiben wird verweigert (kIOReturnNotPrivileged).
    case blocked
    case writable
    /// Vorhanden, Schreibtest ohne eindeutiges Ergebnis.
    case unknown
}

public struct BGChargeCapability: Codable, Equatable, Sendable {
    public static let chargeInhibitKeys = ["CHTE", "CH0B", "CH0C"]
    public static let adapterKeys = ["CHIE", "CH0J", "CH0I"]
    public static let probedKeys = chargeInhibitKeys + adapterKeys

    public var keys: [String: BGSMCKeyState]

    public init(keys: [String: BGSMCKeyState]) { self.keys = keys }

    /// Unbekannte Zustände neuerer Dienste werden zu `.unknown`, statt den Status zu verwerfen.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String: String].self, forKey: .keys) ?? [:]
        keys = raw.mapValues { BGSMCKeyState(rawValue: $0) ?? .unknown }
    }

    private func usable(_ key: String) -> Bool {
        keys[key] == .writable || keys[key] == .unknown
    }

    /// Eine separate Ladesperre ist nutzbar.
    public var chargeInhibitAvailable: Bool { usable("CHTE") || usable("CH0B") }
    public var adapterSwitchAvailable: Bool { Self.adapterKeys.contains(where: usable) }

    /// Die Ladesperre existiert, wurde aber von der Firmware gesperrt.
    public var chargeInhibitBlockedByFirmware: Bool {
        !chargeInhibitAvailable
            && Self.chargeInhibitKeys.contains { keys[$0] == .blocked || keys[$0] == .placeholder }
    }
}

public extension BGStatus {
    /// Separate Ladesperre nutzbar. Ältere Dienste melden nur vorhandene Schlüssel.
    var hasChargeInhibit: Bool {
        chargeCapability?.chargeInhibitAvailable
            ?? smcKeysDetected.contains { $0 == "CHTE" || $0 == "CH0B" }
    }

    var hasAdapterSwitch: Bool {
        chargeCapability?.adapterSwitchAvailable
            ?? smcKeysDetected.contains { BGChargeCapability.adapterKeys.contains($0) }
    }
}

/// Erklärt in Alltagssprache, warum der Mac gerade lädt, hält oder auf 100 % steht.
/// Gründe stehen in absteigender Wichtigkeit; die App zeigt den ersten groß an.
public enum BGChargingReason: Equatable, Sendable {
    case daemonInactive
    case notPluggedIn
    case macOSObservation(nativeLimit: Int?)
    case protectionOff
    case paused(until: Date)
    case heatProtection
    case fullChargeRequested
    case travelCharging(readyAt: Date)
    case topUp
    case adapterFlapping(count: Int)
    case firmwareBlocksChargeInhibit
    /// Ohne Ladesperre hält macOS das Limit.
    case macOSHoldsLimit(nativeLimit: Int?, target: Int)
    /// Ladestand liegt deutlich über Ziel und macOS-Limit – typisch für die gelegentliche
    /// Vollladung, mit der macOS die Ladestandsschätzung kalibriert (Apple 102338).
    case likelyMacOSCalibration(percent: Int, limit: Int)
    case belowLowerLimit(lower: Int, upper: Int)
    case holdingAtLimit(upper: Int)
    case chargingTowardsLimit(upper: Int)
}

public enum BGChargingExplanation {
    /// Ab so vielen Netzteilwechseln pro Stunde gilt die Verbindung als instabil.
    public static let flappingThreshold = 3

    public static func reasons(config: BGConfig, status: BGStatus, daemonActive: Bool,
                               now: Date = Date()) -> [BGChargingReason] {
        guard daemonActive else { return [.daemonInactive] }
        var result: [BGChargingReason] = []
        if let flaps = status.adapterReconnectsLastHour, flaps >= flappingThreshold {
            result.append(.adapterFlapping(count: flaps))
        }
        guard status.pluggedIn else { return result + [.notPluggedIn] }
        if config.mode == .native { return result + [.macOSObservation(nativeLimit: status.nativeChargeLimit)] }
        if !config.enabled { return result + [.protectionOff] }
        if config.isPaused(at: now), let until = config.pauseUntil { return result + [.paused(until: until)] }

        let effective = config.effective(at: now)
        if status.message?.contains("Hitzeschutz") == true { result.append(.heatProtection) }
        if effective.specialChargePlan?.kind == .topUp {
            result.append(.topUp)
        } else if config.isTravelCharging(at: now), let ready = config.travelReadyAt {
            result.append(.travelCharging(readyAt: ready))
        } else if effective.chargeToFullOnce {
            result.append(.fullChargeRequested)
        }

        let capability = status.chargeCapability
        let hasLock = status.hasChargeInhibit
        let target = effective.chargeToFullOnce ? 100 : effective.upperLimit
        if !hasLock {
            if capability?.chargeInhibitBlockedByFirmware == true { result.append(.firmwareBlocksChargeInhibit) }
            let limit = max(status.nativeChargeLimit ?? BGNativeLimitAdvice.nativeMinimum, target)
            if status.percent >= limit + 5, status.percent >= 95 {
                result.append(.likelyMacOSCalibration(percent: status.percent, limit: limit))
            }
            result.append(.macOSHoldsLimit(nativeLimit: status.nativeChargeLimit, target: target))
            return result
        }
        if target < 100, status.percent >= target + 5, status.isChargingHardware || status.percent >= 95 {
            result.append(.likelyMacOSCalibration(percent: status.percent, limit: target))
        }
        if status.percent >= effective.upperLimit {
            result.append(.holdingAtLimit(upper: effective.upperLimit))
        } else if status.percent < effective.lowerLimit {
            result.append(.belowLowerLimit(lower: effective.lowerLimit, upper: effective.upperLimit))
        } else if status.isChargingHardware {
            result.append(.chargingTowardsLimit(upper: effective.upperLimit))
        } else {
            result.append(.holdingAtLimit(upper: effective.upperLimit))
        }
        return result
    }
}

/// Zählt echte Netzteilwechsel. Vom Dienst selbst ausgelöste Trennungen (aktives Entladen)
/// zählen nicht.
public struct BGAdapterFlapCounter: Equatable, Sendable {
    public static let window: TimeInterval = 3600
    private var lastPlugged: Bool?
    private var transitions: [Date] = []

    public init() {}

    public mutating func observe(pluggedIn: Bool, selfInitiated: Bool, at now: Date) -> Int {
        if let lastPlugged, lastPlugged != pluggedIn, !selfInitiated {
            transitions.append(now)
        }
        lastPlugged = pluggedIn
        transitions.removeAll { now.timeIntervalSince($0) > Self.window || now < $0 }
        // Ein Ab- und Anstecken ist ein Wechsel, nicht zwei.
        return transitions.count / 2
    }
}
