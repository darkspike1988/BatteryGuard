import Foundation

/// Vorlagen für häufige Zeitpläne. Sie erzeugen gewöhnliche, eingeschaltete Zeitpläne,
/// die danach wie selbst angelegte bearbeitet oder gelöscht werden können.
public enum BGScheduleTemplate: String, CaseIterable, Identifiable, Sendable {
    /// Montag 5:00 Top Up, damit der Akku zur Arbeitswoche voll ist.
    case mondayTopUp
    /// Samstag 7:00 Top Up bis zum Abstecken, höchstens 24 Stunden.
    case weekendFullCharge
    /// Werktags 17:00 Schreibtisch-Profil, 21:00 zurück zum Alltagsprofil.
    case peakHours

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mondayTopUp: BGLocalized("Montag früh voll laden")
        case .weekendFullCharge: BGLocalized("Wochenende voll laden")
        case .peakHours: BGLocalized("Spitzenlastzeit: abends niedrigeres Limit")
        }
    }

    public var summary: String {
        switch self {
        case .mondayTopUp: BGLocalized("Jeden Montag um 5:00 Top Up für vier Stunden.")
        case .weekendFullCharge: BGLocalized("Jeden Samstag um 7:00 Top Up bis zum Abstecken, höchstens 24 Stunden.")
        case .peakHours: BGLocalized("Werktags um 17:00 das Schreibtisch-Profil, um 21:00 wieder Alltag.")
        }
    }

    /// Zeitpläne ab dem nächsten passenden Termin in der angegebenen Zeitzone.
    public func tasks(now: Date = Date(), timeZone: TimeZone = .current) throws -> [BGScheduledTask] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func next(weekday: Int?, hour: Int) -> Date {
            var components = DateComponents(hour: hour, minute: 0, second: 0)
            components.weekday = weekday
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        }
        func rule(_ name: String, _ start: Date, _ recurrence: ScheduledRule.Recurrence) throws -> ScheduledRule {
            try ScheduledRule(name: name, timeZoneIdentifier: timeZone.identifier, startsAt: start, recurrence: recurrence)
        }
        func profile(_ builtin: BGProfile) throws -> BGScheduledAction {
            BGScheduledAction(kind: .profile, profile: try BGSavedProfile(name: builtin.localizedTitle,
                lowerLimit: builtin.lower, upperLimit: builtin.upper))
        }
        switch self {
        case .mondayTopUp:
            return [BGScheduledTask(schedule: try rule(title, next(weekday: 2, hour: 5), .weekly), enabled: true,
                                    action: BGScheduledAction(kind: .topUp, minutes: 240))]
        case .weekendFullCharge:
            return [BGScheduledTask(schedule: try rule(title, next(weekday: 7, hour: 7), .weekly), enabled: true,
                                    action: BGScheduledAction(kind: .topUp, minutes: 1440))]
        case .peakHours:
            return [
                BGScheduledTask(schedule: try rule(BGLocalized("Spitzenlast beginnt"), next(weekday: nil, hour: 17), .weekdays),
                                enabled: true, action: try profile(.desk)),
                BGScheduledTask(schedule: try rule(BGLocalized("Spitzenlast endet"), next(weekday: nil, hour: 21), .weekdays),
                                enabled: true, action: try profile(.everyday)),
            ]
        }
    }
}
