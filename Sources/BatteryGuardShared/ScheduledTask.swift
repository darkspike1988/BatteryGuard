import Foundation

private struct ScheduleKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func rejectScheduleFields(_ decoder: Decoder, allowed: Set<String>) throws {
    let c = try decoder.container(keyedBy: ScheduleKey.self)
    guard c.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw BGChargingActionError.invalidRequest("Unbekanntes Zeitplanfeld.")
    }
}

public struct BGScheduledAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable, CaseIterable { case profile, topUp, hold, discharge }
    public var kind: Kind
    public var profile: BGSavedProfile?
    public var minutes: Int?
    public var targetPercent: Int?
    public init(kind: Kind, profile: BGSavedProfile? = nil, minutes: Int? = nil, targetPercent: Int? = nil) {
        self.kind = kind; self.profile = profile; self.minutes = minutes; self.targetPercent = targetPercent
    }
    public func validate() throws {
        if let minutes, !(1...1440).contains(minutes) { throw BGChargingActionError.invalidRequest("Ungültige Dauer.") }
        switch kind {
        case .profile:
            guard profile != nil, minutes == nil, targetPercent == nil else { throw BGChargingActionError.invalidRequest("Profil-Zeitplan benötigt nur ein Profil.") }
        case .topUp:
            guard profile == nil, targetPercent == nil || targetPercent == 100 else { throw BGChargingActionError.invalidRequest("Ungültiges Top-Up.") }
        case .hold:
            guard profile == nil, targetPercent == nil else { throw BGChargingActionError.invalidRequest("Halten übernimmt den aktuellen Ladestand.") }
        case .discharge:
            guard profile == nil, let targetPercent, (10...95).contains(targetPercent) else { throw BGChargingActionError.invalidRequest("Ungültiges Entladeziel.") }
        }
    }
    public func request() throws -> BGChargingActionRequest {
        try validate()
        switch kind {
        case .profile: return BGChargingActionRequest(action: .savedProfile, savedProfile: profile)
        case .topUp: return BGChargingActionRequest(action: .topUp, minutes: minutes)
        case .hold: return BGChargingActionRequest(action: .holdCharge, minutes: minutes)
        case .discharge: return BGChargingActionRequest(action: .dischargeTo, minutes: minutes, targetPercent: targetPercent)
        }
    }
    private enum CodingKeys: String, CodingKey { case kind, profile, minutes, targetPercent }
    public init(from decoder: Decoder) throws {
        try rejectScheduleFields(decoder, allowed: ["kind", "profile", "minutes", "targetPercent"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        profile = try c.decodeIfPresent(BGSavedProfile.self, forKey: .profile)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        targetPercent = try c.decodeIfPresent(Int.self, forKey: .targetPercent)
        try validate()
    }
}

public struct BGScheduledTask: Codable, Equatable, Sendable, Identifiable {
    public var schedule: ScheduledRule
    public var enabled: Bool
    public var catchUp: Bool
    public var action: BGScheduledAction
    public var state: BGScheduleExecutionState
    public var id: UUID { schedule.id }
    public init(schedule: ScheduledRule, enabled: Bool = false, catchUp: Bool = false,
                action: BGScheduledAction, state: BGScheduleExecutionState = BGScheduleExecutionState()) {
        self.schedule = schedule; self.enabled = enabled; self.catchUp = catchUp; self.action = action; self.state = state
    }
    public func validated() throws -> Self {
        try ScheduledRule.validate(name: schedule.name, timeZoneIdentifier: schedule.timeZoneIdentifier,
            startsAt: schedule.startsAt, endsAt: schedule.endsAt)
        try action.validate()
        if let d = state.lastOccurrenceDate { try ScheduledRule.validateDate(d, fieldName: "lastOccurrenceDate") }
        if let d = state.lastExecutionDate { try ScheduledRule.validateDate(d, fieldName: "lastExecutionDate") }
        guard state.lastResult.map({ $0.count <= 200 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) ?? true else {
            throw BGChargingActionError.invalidRequest("Ungültiges Zeitplanergebnis.")
        }
        return self
    }
    private enum CodingKeys: String, CodingKey { case schedule, enabled, catchUp, action, state }
    public init(from decoder: Decoder) throws {
        try rejectScheduleFields(decoder, allowed: ["schedule", "enabled", "catchUp", "action", "state"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedule = try c.decode(ScheduledRule.self, forKey: .schedule)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        catchUp = try c.decodeIfPresent(Bool.self, forKey: .catchUp) ?? false
        action = try c.decode(BGScheduledAction.self, forKey: .action)
        state = try c.decodeIfPresent(BGScheduleExecutionState.self, forKey: .state) ?? BGScheduleExecutionState()
        _ = try validated()
    }
}

public struct BGScheduleRun: Codable, Equatable, Sendable {
    public var taskID: UUID
    public var occurrenceAt: Date
    public var executedAt: Date
    public var resultString: String
    public init(taskID: UUID, occurrenceAt: Date, executedAt: Date, resultString: String) {
        self.taskID = taskID; self.occurrenceAt = occurrenceAt; self.executedAt = executedAt; self.resultString = resultString
    }
    private enum CodingKeys: String, CodingKey { case taskID, occurrenceAt, executedAt, resultString }
    public init(from decoder: Decoder) throws {
        try rejectScheduleFields(decoder, allowed: ["taskID", "occurrenceAt", "executedAt", "resultString"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try c.decode(UUID.self, forKey: .taskID)
        occurrenceAt = try c.decode(Date.self, forKey: .occurrenceAt)
        executedAt = try c.decode(Date.self, forKey: .executedAt)
        resultString = try c.decode(String.self, forKey: .resultString)
        try ScheduledRule.validateDate(occurrenceAt, fieldName: "occurrenceAt")
        try ScheduledRule.validateDate(executedAt, fieldName: "executedAt")
        guard resultString.count <= 200, !resultString.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BGChargingActionError.invalidRequest("Ungültiges Zeitplanergebnis.")
        }
    }
}
