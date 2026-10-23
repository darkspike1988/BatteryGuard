import Foundation

/// Welche Regel gerade tatsächlich wirkt – unabhängig davon, was in den Einstellungen steht.
public enum BGControlPath: String, Codable, Sendable {
    case none
    case chargeLock
    /// Nur noch für ältere Dienste (Pendelbetrieb); B-Guard begrenzt so nicht mehr.
    case adapterSwitch
    case macOS

    public init(smcKeys: [String], mode: BGMode) {
        if mode == .native { self = .macOS; return }
        if smcKeys.contains(where: { ["CHTE", "CH0B", "CH0C"].contains($0) }) {
            self = .chargeLock
        } else if smcKeys.contains(where: { ["CHIE", "CH0J", "CH0I"].contains($0) }) {
            // Ohne separate Ladesperre hält macOS das Limit.
            self = .macOS
        } else {
            self = .none
        }
    }

    /// Bevorzugt das Ergebnis des Fähigkeitstests; ältere Dienste melden nur vorhandene Schlüssel.
    public init(status: BGStatus, mode: BGMode) {
        guard mode != .native, let capability = status.chargeCapability else {
            self.init(smcKeys: status.smcKeysDetected, mode: mode)
            return
        }
        if capability.chargeInhibitAvailable {
            self = .chargeLock
        } else if capability.keys.values.contains(where: { $0 != .absent }) {
            self = .macOS
        } else {
            self = .none
        }
    }
}

/// Empfehlung für das macOS-eigene Ladelimit (macOS Tahoe 26.4+, Apple silicon:
/// einstellbar von 80 bis 100 %, siehe support.apple.com/102338).
public struct BGNativeLimitAdvice: Equatable, Sendable {
    public static let nativeMinimum = 80

    /// Kleinster sinnvoller macOS-Wert für das B-Guard-Ziel.
    public let recommendedLimit: Int
    /// Ziel liegt unter dem, was macOS halten kann.
    public let targetBelowNativeMinimum: Bool
    /// Erkanntes macOS-Limit weicht von der Empfehlung ab.
    public let needsAdjustment: Bool

    public init(target: Int, nativeLimit: Int?) {
        let bounded = min(max(target, Self.nativeMinimum), 100)
        recommendedLimit = bounded
        targetBelowNativeMinimum = target < Self.nativeMinimum
        needsAdjustment = nativeLimit.map { $0 != bounded } ?? true
    }
}

public enum BGEffectivenessState: String, Codable, Sendable {
    /// Ziel wird durchgesetzt.
    case effective
    /// macOS-Limit ist niedriger als das B-Guard-Ziel und begrenzt daher zuerst.
    case limitedByNative
    /// Monitor-/Deckelschutz hält das Netzteil verbunden; ohne Ladesperre kann nicht begrenzt werden.
    case desktopFallback
    /// Keine separate Ladesperre: Das macOS-Ladelimit hält den Akku, B-Guard beobachtet.
    case handledByMacOS
    /// Schutz pausiert oder ausgeschaltet.
    case inactive
    /// Keine passende Hardwaresteuerung erkannt.
    case unsupported
    /// Dienst läuft nicht oder liefert keine frischen Werte.
    case daemonInactive
    /// Dienst ist älter als für diese App erforderlich.
    case daemonOutdated
}

public struct BGEffectiveness: Equatable, Sendable {
    public var state: BGEffectivenessState
    public var targetUpperLimit: Int?
    public var appliedUpperLimit: Int?
    public var nativeChargeLimit: Int?
    public var controlPath: BGControlPath
    public var externalDisplayConnected: Bool?
    public var lidClosed: Bool?
    /// Nur bei `handledByMacOS`: welche macOS-Einstellung zum Ziel passt.
    public var nativeAdvice: BGNativeLimitAdvice?

    public init(state: BGEffectivenessState, targetUpperLimit: Int?, appliedUpperLimit: Int?,
                nativeChargeLimit: Int?, controlPath: BGControlPath,
                externalDisplayConnected: Bool? = nil, lidClosed: Bool? = nil) {
        self.state = state
        self.targetUpperLimit = targetUpperLimit
        self.appliedUpperLimit = appliedUpperLimit
        self.nativeChargeLimit = nativeChargeLimit
        self.controlPath = controlPath
        self.externalDisplayConnected = externalDisplayConnected
        self.lidClosed = lidClosed
    }

    public static func evaluate(config: BGConfig, status: BGStatus,
                                daemonActive: Bool, daemonCurrent: Bool,
                                now: Date = Date()) -> BGEffectiveness {
        let effective = config.effective(at: now)
        let native = status.nativeChargeLimit
        let target: Int?
        if config.mode == .native {
            target = native ?? effective.upperLimit
        } else if effective.chargeToFullOnce {
            target = 100
        } else {
            target = effective.upperLimit
        }
        let path = BGControlPath(status: status, mode: config.mode)
        let applied = daemonCurrent ? (status.effectiveUpperLimit ?? target) : nil

        func result(_ state: BGEffectivenessState) -> BGEffectiveness {
            BGEffectiveness(state: state, targetUpperLimit: target, appliedUpperLimit: applied,
                            nativeChargeLimit: native, controlPath: path,
                            externalDisplayConnected: status.externalDisplayConnected,
                            lidClosed: status.lidClosed)
        }

        guard daemonActive else { return result(.daemonInactive) }
        guard daemonCurrent else { return result(.daemonOutdated) }
        if config.mode == .native { return result(.effective) }
        if !config.enabled || config.isPaused(at: now) { return result(.inactive) }
        if path == .macOS, status.state != .unsupported {
            var handled = BGEffectiveness(state: .handledByMacOS, targetUpperLimit: target,
                                          appliedUpperLimit: native, nativeChargeLimit: native, controlPath: path,
                                          externalDisplayConnected: status.externalDisplayConnected,
                                          lidClosed: status.lidClosed)
            handled.nativeAdvice = target.map { BGNativeLimitAdvice(target: $0, nativeLimit: native) }
            return handled
        }
        if status.state == .unsupported || path == .none { return result(.unsupported) }
        if status.state == .disabled,
           status.adapterDisconnectAllowed == false,
           status.externalDisplayConnected == true || status.lidClosed == true {
            return result(.desktopFallback)
        }
        if let native, let target, native < target { return result(.limitedByNative) }
        return result(.effective)
    }
}
