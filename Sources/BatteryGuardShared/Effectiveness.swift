import Foundation

/// Welche Regel gerade tatsächlich wirkt – unabhängig davon, was in den Einstellungen steht.
public enum BGControlPath: String, Codable, Sendable {
    case none
    case chargeLock
    case adapterSwitch
    case macOS

    public init(smcKeys: [String], mode: BGMode) {
        if mode == .native { self = .macOS; return }
        if smcKeys.contains(where: { ["CHTE", "CH0B", "CH0C"].contains($0) }) {
            self = .chargeLock
        } else if smcKeys.contains(where: { ["CHIE", "CH0J", "CH0I"].contains($0) }) {
            self = .adapterSwitch
        } else {
            self = .none
        }
    }
}

public enum BGEffectivenessState: String, Codable, Sendable {
    /// Ziel wird durchgesetzt.
    case effective
    /// macOS-Limit ist niedriger als das B-Guard-Ziel und begrenzt daher zuerst.
    case limitedByNative
    /// Monitor-/Deckelschutz hält das Netzteil verbunden; ohne Ladesperre kann nicht begrenzt werden.
    case desktopFallback
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
        let path = BGControlPath(smcKeys: status.smcKeysDetected, mode: config.mode)
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
