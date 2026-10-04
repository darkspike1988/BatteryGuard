import Foundation

public enum BGChargingAction: String, Codable, CaseIterable, Sendable {
    case profile, protection, pause, resume, travel
    case fullCharge = "full-charge"
    case cancelFullCharge = "cancel-full-charge"
    case cancelTravel = "cancel-travel"
}

public enum BGChargingActionError: Error, LocalizedError, Equatable, Sendable {
    case invalidRequest(String)
    case unsupportedMode

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): return reason
        case .unsupportedMode:
            return "Diese Aktion braucht B-Guard-Steuerung. Bitte zuerst ein Ladeprofil aktivieren oder den Schutz starten."
        }
    }
}

/// The UI and local API apply the same validated, side-effect-free configuration changes.
public struct BGChargingActionRequest: Codable, Equatable, Sendable {
    public var action: BGChargingAction
    public var profile: String?
    public var enabled: Bool?
    public var minutes: Int?
    public var readyAt: Date?

    public init(action: BGChargingAction, profile: String? = nil, enabled: Bool? = nil,
                minutes: Int? = nil, readyAt: Date? = nil) {
        self.action = action
        self.profile = profile
        self.enabled = enabled
        self.minutes = minutes
        self.readyAt = readyAt
    }

    private enum CodingKeys: String, CodingKey {
        case action, profile, enabled, minutes, readyAt
    }
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(BGChargingAction.self, forKey: .action)
        let all = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Self.allowedFields(for: action)
        guard all.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw BGChargingActionError.invalidRequest("Unbekannte oder für diese Aktion unzulässige Felder.")
        }
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        readyAt = try container.decodeIfPresent(Date.self, forKey: .readyAt)
        try validateParameters()
    }

    private static func allowedFields(for action: BGChargingAction) -> Set<String> {
        switch action {
        case .profile: return ["action", "profile"]
        case .protection: return ["action", "enabled"]
        case .pause: return ["action", "minutes"]
        case .travel: return ["action", "readyAt"]
        case .resume, .fullCharge, .cancelFullCharge, .cancelTravel: return ["action"]
        }
    }

    private func validateParameters() throws {
        let supplied = [profile != nil ? "profile" : nil,
                        enabled != nil ? "enabled" : nil,
                        minutes != nil ? "minutes" : nil,
                        readyAt != nil ? "readyAt" : nil].compactMap { $0 }
        guard supplied.allSatisfy(Self.allowedFields(for: action).contains) else {
            throw BGChargingActionError.invalidRequest("Für diese Aktion unzulässige Felder.")
        }
        switch action {
        case .profile:
            guard let profile, BGProfile(rawValue: profile) != nil else {
                throw BGChargingActionError.invalidRequest("Profil muss desk, everyday oder mobile sein.")
            }
        case .protection:
            guard enabled != nil else { throw BGChargingActionError.invalidRequest("enabled muss true oder false sein.") }
        case .pause:
            guard let minutes, (1...720).contains(minutes) else {
                throw BGChargingActionError.invalidRequest("Eine Pause muss zwischen 1 und 720 Minuten dauern.")
            }
        case .travel:
            guard let readyAt, readyAt.timeIntervalSince1970.isFinite else {
                throw BGChargingActionError.invalidRequest("Ein gültiger Reisezeitpunkt ist erforderlich.")
            }
        case .resume, .fullCharge, .cancelFullCharge, .cancelTravel: break
        }
    }

    public func applying(to config: BGConfig, at now: Date = Date()) throws -> BGConfig {
        try validateParameters()
        guard now.timeIntervalSince1970.isFinite else {
            throw BGChargingActionError.invalidRequest("Ungültiger aktueller Zeitpunkt.")
        }
        if [.pause, .resume, .fullCharge, .travel].contains(action),
           config.mode == .native || config.mode == .direct {
            throw BGChargingActionError.unsupportedMode
        }
        if action == .travel, let readyAt,
           !(readyAt > now && readyAt.timeIntervalSince(now) <= 30 * 24 * 3600) {
            throw BGChargingActionError.invalidRequest("Der Reisezeitpunkt muss in der Zukunft und innerhalb von 30 Tagen liegen.")
        }
        var next = config
        switch action {
        case .profile:
            // Already validated; avoid force-unwrapping even for programmatic requests.
            guard let profile, let selected = BGProfile(rawValue: profile) else {
                throw BGChargingActionError.invalidRequest("Ungültiges Profil.")
            }
            next = selected.applying(to: next)
            if next.mode == .native || next.mode == .direct { next.mode = .auto }
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
            if next.isTravelCharging(at: now) { next.travelReadyAt = nil }
        case .protection:
            guard let enabled else { throw BGChargingActionError.invalidRequest("enabled fehlt.") }
            next.enabled = enabled
            next.pauseUntil = nil
            if enabled && (next.mode == .native || next.mode == .direct) { next.mode = .auto }
        case .pause:
            guard let minutes else { throw BGChargingActionError.invalidRequest("minutes fehlt.") }
            next.pauseUntil = now.addingTimeInterval(Double(minutes) * 60)
        case .resume: next.pauseUntil = nil
        case .fullCharge:
            next.enabled = true
            next.pauseUntil = nil
            next.chargeToFullOnce = true
            next.fullChargeUntil = now.addingTimeInterval(8 * 3600)
            next.fullChargeRequestID = UUID()
        case .cancelFullCharge:
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
            if next.isTravelCharging(at: now) { next.travelReadyAt = nil }
        case .travel:
            next.enabled = true
            next.pauseUntil = nil
            next.travelReadyAt = readyAt
            next.travelRequestID = UUID()
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
        case .cancelTravel: next.travelReadyAt = nil
        }
        return next.sanitized()
    }
}
