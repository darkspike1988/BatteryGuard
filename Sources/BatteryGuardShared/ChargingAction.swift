import Foundation

public enum BGChargingAction: String, Codable, CaseIterable, Sendable {
    case profile, protection, pause, resume, travel
    case savedProfile = "saved-profile"
    case upsertSchedule = "upsert-schedule"
    case deleteSchedule = "delete-schedule"
    case calibration = "calibration"
    case cancelCalibration = "cancel-calibration"
    case stayAwakeUntilLimit = "stay-awake-until-limit"
    case cancelStayAwake = "cancel-stay-awake"
    case fullCharge = "full-charge"
    case cancelFullCharge = "cancel-full-charge"
    case cancelTravel = "cancel-travel"
    case topUp = "top-up"
    case dischargeTo = "discharge-to"
    case holdCharge = "hold-charge"
    case cancelSpecial = "cancel-special"
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
    public var targetPercent: Int?
    public var savedProfile: BGSavedProfile?
    public var scheduledTask: BGScheduledTask?
    public var scheduleID: UUID?

    public init(action: BGChargingAction, profile: String? = nil, enabled: Bool? = nil,
                minutes: Int? = nil, readyAt: Date? = nil, targetPercent: Int? = nil, savedProfile: BGSavedProfile? = nil, scheduledTask: BGScheduledTask? = nil, scheduleID: UUID? = nil) {
        self.action = action
        self.profile = profile
        self.enabled = enabled
        self.minutes = minutes
        self.readyAt = readyAt
        self.targetPercent = targetPercent
        self.savedProfile = savedProfile
        self.scheduledTask = scheduledTask
        self.scheduleID = scheduleID
    }

    private enum CodingKeys: String, CodingKey {
        case action, profile, enabled, minutes, readyAt, targetPercent, savedProfile, scheduledTask, scheduleID
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
        targetPercent = try container.decodeIfPresent(Int.self, forKey: .targetPercent)
        savedProfile = try container.decodeIfPresent(BGSavedProfile.self, forKey: .savedProfile)
        scheduledTask = try container.decodeIfPresent(BGScheduledTask.self, forKey: .scheduledTask)
        scheduleID = try container.decodeIfPresent(UUID.self, forKey: .scheduleID)
        try validateParameters()
    }

    private static func allowedFields(for action: BGChargingAction) -> Set<String> {
        switch action {
        case .upsertSchedule: return ["action", "scheduledTask"]
        case .deleteSchedule: return ["action", "scheduleID"]
        case .savedProfile: return ["action", "savedProfile"]
        case .profile: return ["action", "profile"]
        case .protection: return ["action", "enabled"]
        case .pause, .stayAwakeUntilLimit: return ["action", "minutes"]
        case .travel: return ["action", "readyAt"]
        case .cancelStayAwake, .calibration, .cancelCalibration, .resume, .fullCharge, .cancelFullCharge, .cancelTravel, .cancelSpecial: return ["action"]
        case .topUp: return ["action", "minutes", "targetPercent"]
        case .dischargeTo, .holdCharge: return ["action", "targetPercent", "minutes"]
        }
    }

    private func validateParameters() throws {
        let supplied = [profile != nil ? "profile" : nil,
                        enabled != nil ? "enabled" : nil,
                        minutes != nil ? "minutes" : nil,
                        readyAt != nil ? "readyAt" : nil,
                        targetPercent != nil ? "targetPercent" : nil,
                        savedProfile != nil ? "savedProfile" : nil, scheduledTask != nil ? "scheduledTask" : nil,
                        scheduleID != nil ? "scheduleID" : nil].compactMap { $0 }
        guard supplied.allSatisfy(Self.allowedFields(for: action).contains) else {
            throw BGChargingActionError.invalidRequest("Für diese Aktion unzulässige Felder.")
        }
        switch action {
        case .upsertSchedule:
            guard let scheduledTask else { throw BGChargingActionError.invalidRequest("Zeitplan fehlt.") }
            _ = try scheduledTask.validated()
        case .deleteSchedule:
            guard scheduleID != nil else { throw BGChargingActionError.invalidRequest("Zeitplan-ID fehlt.") }
        case .savedProfile:
            guard savedProfile != nil else { throw BGChargingActionError.invalidRequest("Gespeichertes Profil fehlt.") }
        case .profile:
            guard let profile, BGProfile(rawValue: profile) != nil else {
                throw BGChargingActionError.invalidRequest("Profil muss desk, everyday oder mobile sein.")
            }
        case .protection:
            guard enabled != nil else { throw BGChargingActionError.invalidRequest("enabled muss true oder false sein.") }
        case .stayAwakeUntilLimit:
            guard let minutes, (1...120).contains(minutes) else { throw BGChargingActionError.invalidRequest("Wachhalten benötigt 1 bis 120 Minuten.") }
        case .pause:
            guard let minutes, (1...720).contains(minutes) else {
                throw BGChargingActionError.invalidRequest("Eine Pause muss zwischen 1 und 720 Minuten dauern.")
            }
        case .travel:
            guard let readyAt, readyAt.timeIntervalSince1970.isFinite else {
                throw BGChargingActionError.invalidRequest("Ein gültiger Reisezeitpunkt ist erforderlich.")
            }
        case .cancelStayAwake, .calibration, .cancelCalibration, .resume, .fullCharge, .cancelFullCharge, .cancelTravel, .cancelSpecial: break
        case .topUp:
            if let targetPercent, targetPercent != 100 {
                throw BGChargingActionError.invalidRequest("Top-Up lädt immer auf 100 %.")
            }
            if let minutes, !(1...1440).contains(minutes) {
                throw BGChargingActionError.invalidRequest("Dauer muss zwischen 1 und 1440 Minuten liegen.")
            }
        case .dischargeTo:
            guard let targetPercent, (10...95).contains(targetPercent) else {
                throw BGChargingActionError.invalidRequest("Ziel-Ladestand muss zwischen 10 und 95 liegen.")
            }
            if let minutes, !(1...1440).contains(minutes) {
                throw BGChargingActionError.invalidRequest("Dauer muss zwischen 1 und 1440 Minuten liegen.")
            }
        case .holdCharge:
            if let targetPercent, !(10...95).contains(targetPercent) {
                throw BGChargingActionError.invalidRequest("Ziel-Ladestand zum Halten muss zwischen 10 und 95 liegen.")
            }
            if let minutes, !(1...1440).contains(minutes) {
                throw BGChargingActionError.invalidRequest("Dauer muss zwischen 1 und 1440 Minuten liegen.")
            }
        }
    }

    public func applying(to config: BGConfig, at now: Date = Date()) throws -> BGConfig {
        try validateParameters()
        guard now.timeIntervalSince1970.isFinite else {
            throw BGChargingActionError.invalidRequest("Ungültiger aktueller Zeitpunkt.")
        }
        if [.pause, .resume, .fullCharge, .travel, .topUp, .dischargeTo, .holdCharge, .stayAwakeUntilLimit].contains(action),
           config.mode == .native || config.mode == .direct {
            throw BGChargingActionError.unsupportedMode
        }
        if action == .travel, let readyAt,
           !(readyAt > now && readyAt.timeIntervalSince(now) <= 30 * 24 * 3600) {
            throw BGChargingActionError.invalidRequest("Der Reisezeitpunkt muss in der Zukunft und innerhalb von 30 Tagen liegen.")
        }
        var next = config
        if action != .upsertSchedule && action != .deleteSchedule && action != .stayAwakeUntilLimit && action != .cancelStayAwake {
            next.manualOverrideUntil = now.addingTimeInterval(2 * 3600)
            next.calibrationPlan = nil
        }
        switch action {
        case .stayAwakeUntilLimit:
            guard let minutes else { throw BGChargingActionError.invalidRequest("Dauer fehlt.") }
            next.awakeUntilLimitUntil = now.addingTimeInterval(Double(minutes) * 60)
        case .cancelStayAwake:
            next.awakeUntilLimitUntil = nil
        case .calibration:
            next.enabled = true
            next.pauseUntil = nil
            next.specialChargePlan = nil
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
            if next.isTravelCharging(at: now) { next.travelReadyAt = nil }
            next.calibrationPlan = BGCalibrationPlan.manuallyStarted(at: now)
        case .cancelCalibration:
            next.calibrationPlan = nil
        case .upsertSchedule:
            guard var task = scheduledTask else { throw BGChargingActionError.invalidRequest("Zeitplan fehlt.") }
            task = try task.validated()
            if let index = next.scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                task.state = next.scheduledTasks[index].state
                next.scheduledTasks[index] = task
            } else {
                guard next.scheduledTasks.count < 50 else { throw BGChargingActionError.invalidRequest("Maximal 50 Zeitpläne sind erlaubt.") }
                task.state = BGScheduleExecutionState()
                next.scheduledTasks.append(task)
            }
        case .deleteSchedule:
            guard let scheduleID else { throw BGChargingActionError.invalidRequest("Zeitplan-ID fehlt.") }
            next.scheduledTasks.removeAll { $0.id == scheduleID }
        case .savedProfile:
            guard let savedProfile else { throw BGChargingActionError.invalidRequest("Gespeichertes Profil fehlt.") }
            next = savedProfile.applying(to: next)
            if next.isTravelCharging(at: now) { next.travelReadyAt = nil; next.travelRequestID = nil }
        case .profile:
            // Already validated; avoid force-unwrapping even for programmatic requests.
            guard let profile, let selected = BGProfile(rawValue: profile) else {
                throw BGChargingActionError.invalidRequest("Ungültiges Profil.")
            }
            next = selected.applying(to: next)
            if next.mode == .native || next.mode == .direct { next.mode = .auto }
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
            next.specialChargePlan = nil
            if next.isTravelCharging(at: now) { next.travelReadyAt = nil }
        case .protection:
            guard let enabled else { throw BGChargingActionError.invalidRequest("enabled fehlt.") }
            next.enabled = enabled
            next.pauseUntil = nil
            if !enabled { next.specialChargePlan = nil; next.awakeUntilLimitUntil = nil }
            if enabled && (next.mode == .native || next.mode == .direct) { next.mode = .auto }
        case .pause:
            next.awakeUntilLimitUntil = nil
            next.specialChargePlan = nil
            guard let minutes else { throw BGChargingActionError.invalidRequest("minutes fehlt.") }
            next.pauseUntil = now.addingTimeInterval(Double(minutes) * 60)
        case .resume: next.pauseUntil = nil
        case .fullCharge:
            next.specialChargePlan = nil
            next.enabled = true
            next.pauseUntil = nil
            next.chargeToFullOnce = true
            next.fullChargeUntil = now.addingTimeInterval(8 * 3600)
            next.fullChargeRequestID = UUID()
        case .cancelFullCharge:
            if next.specialChargePlan?.kind == .topUp { next.specialChargePlan = nil }
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
            if next.isTravelCharging(at: now) { next.travelReadyAt = nil }
        case .travel:
            next.specialChargePlan = nil
            next.enabled = true
            next.pauseUntil = nil
            next.travelReadyAt = readyAt
            next.travelRequestID = UUID()
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
        case .cancelTravel: next.travelReadyAt = nil
        case .topUp, .dischargeTo, .holdCharge:
            next.enabled = true
            next.pauseUntil = nil
            next.chargeToFullOnce = false
            next.fullChargeUntil = nil
            next.fullChargeRequestID = nil
            if next.isTravelCharging(at: now) {
                next.travelReadyAt = nil
                next.travelRequestID = nil
            }
            let durationMinutes = minutes ?? (8 * 60)
            let boundedDuration = min(max(Double(durationMinutes) * 60, 60), 24 * 3600)
            let expiresAt = now.addingTimeInterval(boundedDuration)
            let kind: BGSpecialPlanKind
            let target: Int
            switch action {
            case .topUp:
                kind = .topUp
                target = 100
            case .dischargeTo:
                kind = .discharge
                guard let value = targetPercent else { throw BGChargingActionError.invalidRequest("Ziel fehlt.") }
                target = value
            case .holdCharge:
                kind = .hold
                guard let value = targetPercent else { throw BGChargingActionError.invalidRequest("Ziel fehlt.") }
                target = value
            default:
                throw BGChargingActionError.invalidRequest("Ungültige Sonderaktion.")
            }
            next.specialChargePlan = BGSpecialChargePlan(
                requestID: UUID(),
                kind: kind,
                targetPercent: target,
                createdAt: now,
                expiresAt: expiresAt,
                hasObservedPower: false
            )
        case .cancelSpecial:
            next.specialChargePlan = nil
        }
        return next.sanitized()
    }
}
