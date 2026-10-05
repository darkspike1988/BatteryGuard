import Foundation

/// Pure Foundation Swift 6 immutable schedule model for BatteryGuard.
public struct ScheduledRule: Codable, Equatable, Sendable, Identifiable {
    /// Recurrence intervals supported by the schedule.
    public enum Recurrence: String, Codable, Equatable, Sendable, CaseIterable {
        case once
        case daily
        case weekdays
        case weekly
        case biweekly
        case monthly
        case yearly
    }

    /// Validation errors thrown by `ScheduledRule`.
    public enum ValidationError: Error, Equatable, Sendable, LocalizedError {
        case nameTooLong(Int)
        case emptyName
        case nameContainsControlCharacters
        case invalidTimeZone(String)
        case nonFiniteDate(String)
        case endsAtBeforeStartsAt(startsAt: Date, endsAt: Date)

        public var errorDescription: String? {
            switch self {
            case .emptyName: return "Ein Name ist erforderlich."
            case .nameTooLong(let count):
                return "Schedule name exceeds 60 characters (actual length: \(count))."
            case .nameContainsControlCharacters:
                return "Schedule name must not contain control characters or newlines."
            case .invalidTimeZone(let identifier):
                return "Invalid time zone identifier: '\(identifier)'."
            case .nonFiniteDate(let field):
                return "Date for '\(field)' must be a finite, valid date."
            case .endsAtBeforeStartsAt(let startsAt, let endsAt):
                return "endsAt (\(endsAt)) must be greater than or equal to startsAt (\(startsAt))."
            }
        }
    }

    public let id: UUID
    public let name: String
    public let timeZoneIdentifier: String
    public let startsAt: Date
    public let endsAt: Date?
    public let recurrence: Recurrence

    public var timeZone: TimeZone {
        // Guaranteed valid by validation on construction.
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    public var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// Creates and validates an immutable `ScheduledRule`.
    public init(
        id: UUID = UUID(),
        name: String,
        timeZoneIdentifier: String,
        startsAt: Date,
        endsAt: Date? = nil,
        recurrence: Recurrence
    ) throws {
        try Self.validate(
            name: name,
            timeZoneIdentifier: timeZoneIdentifier,
            startsAt: startsAt,
            endsAt: endsAt
        )
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.recurrence = recurrence
    }

    // MARK: - Validation

    public static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.emptyName }
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).count <= 60 else {
            throw ValidationError.nameTooLong(name.count)
        }
        for scalar in name.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                throw ValidationError.nameContainsControlCharacters
            }
        }
    }

    public static func validateTimeZone(_ identifier: String) throws {
        guard TimeZone(identifier: identifier) != nil else {
            throw ValidationError.invalidTimeZone(identifier)
        }
    }

    public static func validateDate(_ date: Date, fieldName: String) throws {
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite, (0...7_258_118_400).contains(date.timeIntervalSince1970) else {
            throw ValidationError.nonFiniteDate(fieldName)
        }
    }

    public static func validate(
        name: String,
        timeZoneIdentifier: String,
        startsAt: Date,
        endsAt: Date?
    ) throws {
        try validateName(name)
        try validateTimeZone(timeZoneIdentifier)
        try validateDate(startsAt, fieldName: "startsAt")
        if let endsAt = endsAt {
            try validateDate(endsAt, fieldName: "endsAt")
            guard endsAt >= startsAt else {
                throw ValidationError.endsAtBeforeStartsAt(startsAt: startsAt, endsAt: endsAt)
            }
        }
    }

    // MARK: - Codable (Rejects Unknown Fields & Validates)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case timeZoneIdentifier
        case startsAt
        case endsAt
        case recurrence
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    public init(from decoder: Decoder) throws {
        // Enforce rejection of unknown fields
        let anyContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        let validKeys = Set(CodingKeys.allCases.map(\.stringValue))
        for key in anyContainer.allKeys {
            if !validKeys.contains(key.stringValue) {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: anyContainer.codingPath + [key],
                        debugDescription: "Unknown field '\(key.stringValue)' rejected by ScheduledRule"
                    )
                )
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        let startsAt = try container.decode(Date.self, forKey: .startsAt)
        let endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        let recurrence = try container.decode(Recurrence.self, forKey: .recurrence)

        do {
            try Self.validate(
                name: name,
                timeZoneIdentifier: timeZoneIdentifier,
                startsAt: startsAt,
                endsAt: endsAt
            )
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ScheduledRule validation failed: \(error.localizedDescription)",
                    underlyingError: error
                )
            )
        }

        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.recurrence = recurrence
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encode(recurrence, forKey: .recurrence)
    }

    // MARK: - Wall-Clock Calculation Helpers

    private var wallClockTime: (hour: Int, minute: Int, second: Int) {
        let cal = self.calendar
        let comps = cal.dateComponents([.hour, .minute, .second], from: startsAt)
        return (comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
    }

    /// Computes the occurrence on `day` applying wall-clock hour/minute/second from `startsAt`.
    /// Resolves DST nonexistent gaps using `.nextTime` and repeated ambiguous times using `.first`.
    private func occurrence(onDay day: Date, calendar cal: Calendar) -> Date? {
        if cal.isDate(day, inSameDayAs: startsAt) { return startsAt }
        let time = wallClockTime
        let dayStart = cal.startOfDay(for: day)
        return cal.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: time.second,
            of: dayStart,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    /// Validates month length and computes occurrence on month/day-of-month. Skips invalid months (e.g. Feb 31).
    private func monthlyOccurrence(year: Int, month: Int, calendar cal: Calendar) -> Date? {
        let startComps = cal.dateComponents([.day], from: startsAt)
        guard let targetDay = startComps.day else { return nil }

        var monthComps = DateComponents()
        monthComps.year = year
        monthComps.month = month
        monthComps.day = 1
        guard let firstOfMonth = cal.date(from: monthComps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth),
              range.contains(targetDay) else {
            return nil
        }

        monthComps.day = targetDay
        guard let targetDate = cal.date(from: monthComps) else { return nil }
        return occurrence(onDay: targetDate, calendar: cal)
    }

    /// Validates year length and computes occurrence on month/day-of-year. Skips invalid non-leap years (e.g. Feb 29).
    private func yearlyOccurrence(year: Int, calendar cal: Calendar) -> Date? {
        let startComps = cal.dateComponents([.month, .day], from: startsAt)
        guard let targetMonth = startComps.month, let targetDay = startComps.day else { return nil }

        var comps = DateComponents()
        comps.year = year
        comps.month = targetMonth
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth),
              range.contains(targetDay) else {
            return nil
        }

        comps.day = targetDay
        guard let targetDate = cal.date(from: comps) else { return nil }
        return occurrence(onDay: targetDate, calendar: cal)
    }

    // MARK: - Next Occurrence (Strictly Later)

    /// Returns the next occurrence strictly later than `after`.
    /// If `after < startsAt`, returns the first legal occurrence on or after `startsAt`.
    public func nextOccurrence(after date: Date) -> Date? {
        if let endsAt = endsAt, date >= endsAt {
            return nil
        }
        let cal = self.calendar
        let isBeforeStart = date < startsAt

        switch recurrence {
        case .once:
            if isBeforeStart {
                if let occ = occurrence(onDay: startsAt, calendar: cal) {
                    if occ > date && (endsAt == nil || occ <= endsAt!) {
                        return occ
                    }
                } else if startsAt > date && (endsAt == nil || startsAt <= endsAt!) {
                    return startsAt
                }
            }
            return nil

        case .daily:
            let baseDate = isBeforeStart ? startsAt : date
            let day0 = cal.startOfDay(for: baseDate)
            for offset in 0...2 {
                guard let candidateDay = cal.date(byAdding: .day, value: offset, to: day0) else { continue }
                if let occ = occurrence(onDay: candidateDay, calendar: cal) {
                    let isLegal = isBeforeStart ? (occ >= startsAt) : (occ > date)
                    if isLegal {
                        return (endsAt == nil || occ <= endsAt!) ? occ : nil
                    }
                }
            }
            return nil

        case .weekdays:
            let baseDate = isBeforeStart ? startsAt : date
            let day0 = cal.startOfDay(for: baseDate)
            for offset in 0...7 {
                guard let candidateDay = cal.date(byAdding: .day, value: offset, to: day0) else { continue }
                let weekday = cal.component(.weekday, from: candidateDay)
                if (2...6).contains(weekday) {
                    if let occ = occurrence(onDay: candidateDay, calendar: cal) {
                        let isLegal = isBeforeStart ? (occ >= startsAt) : (occ > date)
                        if isLegal {
                            return (endsAt == nil || occ <= endsAt!) ? occ : nil
                        }
                    }
                }
            }
            return nil

        case .weekly:
            let targetWeekday = cal.component(.weekday, from: startsAt)
            let baseDate = isBeforeStart ? startsAt : date
            let day0 = cal.startOfDay(for: baseDate)
            for offset in 0...8 {
                guard let candidateDay = cal.date(byAdding: .day, value: offset, to: day0) else { continue }
                if cal.component(.weekday, from: candidateDay) == targetWeekday {
                    if let occ = occurrence(onDay: candidateDay, calendar: cal) {
                        let isLegal = isBeforeStart ? (occ >= startsAt) : (occ > date)
                        if isLegal {
                            return (endsAt == nil || occ <= endsAt!) ? occ : nil
                        }
                    }
                }
            }
            return nil

        case .biweekly:
            // 14 calendar days anchored to local date of startsAt
            let anchorDay = cal.startOfDay(for: startsAt)
            let baseDate = isBeforeStart ? startsAt : date
            let baseDay = cal.startOfDay(for: baseDate)
            let totalDays = cal.dateComponents([.day], from: anchorDay, to: baseDay).day ?? 0
            let startK = max(0, totalDays / 14)
            for step in startK...(startK + 2) {
                guard let candidateDay = cal.date(byAdding: .day, value: step * 14, to: anchorDay) else { continue }
                if let occ = occurrence(onDay: candidateDay, calendar: cal) {
                    let isLegal = isBeforeStart ? (occ >= startsAt) : (occ > date)
                    if isLegal {
                        return (endsAt == nil || occ <= endsAt!) ? occ : nil
                    }
                }
            }
            return nil

        case .monthly:
            let baseDate = isBeforeStart ? startsAt : date
            let baseYear = cal.component(.year, from: baseDate)
            let baseMonth = cal.component(.month, from: baseDate)
            for offset in 0...12 {
                let totalMonth = (baseYear * 12 + (baseMonth - 1)) + offset
                let y = totalMonth / 12
                let m = (totalMonth % 12) + 1
                if let occ = monthlyOccurrence(year: y, month: m, calendar: cal) {
                    let isLegal = isBeforeStart ? (occ >= startsAt) : (occ > date)
                    if isLegal {
                        return (endsAt == nil || occ <= endsAt!) ? occ : nil
                    }
                }
            }
            return nil

        case .yearly:
            let baseDate = isBeforeStart ? startsAt : date
            let baseYear = cal.component(.year, from: baseDate)
            for y in baseYear...(baseYear + 8) {
                if let occ = yearlyOccurrence(year: y, calendar: cal) {
                    let isLegal = isBeforeStart ? (occ >= startsAt) : (occ > date)
                    if isLegal {
                        return (endsAt == nil || occ <= endsAt!) ? occ : nil
                    }
                }
            }
            return nil
        }
    }

    // MARK: - Bounded Calendar Search (Most Recent Occurrence)

    /// Returns the most recent occurrence scheduled on or before `date`.
    /// Uses bounded calendar search with a maximum horizon of 8 years for leap yearly (never looping unbounded millions).
    public func mostRecentOccurrence(at date: Date) -> Date? {
        if date < startsAt {
            return nil
        }
        let cal = self.calendar
        let effectiveDate = (endsAt != nil) ? min(date, endsAt!) : date
        if effectiveDate < startsAt {
            return nil
        }

        switch recurrence {
        case .once:
            if let occ = occurrence(onDay: startsAt, calendar: cal) {
                if occ <= effectiveDate && occ >= startsAt {
                    return occ
                }
            } else if startsAt <= effectiveDate {
                return startsAt
            }
            return nil

        case .daily:
            let day0 = cal.startOfDay(for: effectiveDate)
            if let occ = occurrence(onDay: day0, calendar: cal), occ <= effectiveDate, occ >= startsAt {
                return occ
            }
            if let dayPrev = cal.date(byAdding: .day, value: -1, to: day0),
               let occ = occurrence(onDay: dayPrev, calendar: cal), occ <= effectiveDate, occ >= startsAt {
                return occ
            }
            return nil

        case .weekdays:
            let day0 = cal.startOfDay(for: effectiveDate)
            for offset in 0...4 {
                guard let candidateDay = cal.date(byAdding: .day, value: -offset, to: day0) else { continue }
                let weekday = cal.component(.weekday, from: candidateDay)
                if (2...6).contains(weekday) {
                    if let occ = occurrence(onDay: candidateDay, calendar: cal), occ <= effectiveDate, occ >= startsAt {
                        return occ
                    }
                }
            }
            return nil

        case .weekly:
            let targetWeekday = cal.component(.weekday, from: startsAt)
            let day0 = cal.startOfDay(for: effectiveDate)
            for offset in 0...7 {
                guard let candidateDay = cal.date(byAdding: .day, value: -offset, to: day0) else { continue }
                if cal.component(.weekday, from: candidateDay) == targetWeekday {
                    if let occ = occurrence(onDay: candidateDay, calendar: cal), occ <= effectiveDate, occ >= startsAt {
                        return occ
                    }
                }
            }
            return nil

        case .biweekly:
            let anchorDay = cal.startOfDay(for: startsAt)
            let currentDay = cal.startOfDay(for: effectiveDate)
            guard let totalDays = cal.dateComponents([.day], from: anchorDay, to: currentDay).day,
                  totalDays >= 0 else {
                return nil
            }
            let k = totalDays / 14
            for step in stride(from: k, through: max(0, k - 1), by: -1) {
                guard let candidateDay = cal.date(byAdding: .day, value: step * 14, to: anchorDay) else { continue }
                if let occ = occurrence(onDay: candidateDay, calendar: cal), occ <= effectiveDate, occ >= startsAt {
                    return occ
                }
            }
            return nil

        case .monthly:
            let currentYear = cal.component(.year, from: effectiveDate)
            let currentMonth = cal.component(.month, from: effectiveDate)
            for offset in 0...3 {
                let totalMonth = (currentYear * 12 + (currentMonth - 1)) - offset
                let y = totalMonth / 12
                let m = (totalMonth % 12) + 1
                if let occ = monthlyOccurrence(year: y, month: m, calendar: cal) {
                    if occ <= effectiveDate && occ >= startsAt {
                        return occ
                    }
                }
            }
            return nil

        case .yearly:
            let currentYear = cal.component(.year, from: effectiveDate)
            let startYear = cal.component(.year, from: startsAt)
            let minYear = max(currentYear - 8, startYear)
            for y in stride(from: currentYear, through: minYear, by: -1) {
                if let occ = yearlyOccurrence(year: y, calendar: cal) {
                    if occ <= effectiveDate && occ >= startsAt {
                        return occ
                    }
                }
            }
            return nil
        }
    }

    // MARK: - Pending Occurrence Execution Logic

    /// Evaluates if there is an unexecuted occurrence pending at `date`.
    /// - Newest only: only the single most recent occurrence `<= date` is considered.
    /// - Catch-up: missed occurrences run only if `catchUp == true` and `age <= 6 hours`.
    /// - Duplicate prevention: does not execute if `state.lastOccurrenceDate >= candidate`.
    /// - Override suppression: suppresses while override is active, and suppressed occurrences `<= manualOverrideUntil`
    ///   do not execute even after override expires.
    /// - Clock backward: if `date < state.lastExecutionDate`, no execution occurs.
    public func pendingOccurrence(
        at date: Date,
        state: BGScheduleExecutionState,
        catchUp: Bool,
        manualOverrideUntil: Date?
    ) -> Date? {
        if let endsAt, date > endsAt { return nil }
        guard date.timeIntervalSince1970.isFinite else { return nil }
        // Clock backward protection
        if let lastExec = state.lastExecutionDate, date < lastExec {
            return nil
        }

        // Newest only: most recent scheduled occurrence <= date
        guard let candidate = mostRecentOccurrence(at: date) else {
            return nil
        }

        // Duplicate prevention
        if let lastOcc = state.lastOccurrenceDate, candidate <= lastOcc {
            return nil
        }

        // Manual override suppression
        if let overrideUntil = manualOverrideUntil {
            if date < overrideUntil || candidate <= overrideUntil {
                return nil
            }
        }

        // Timing & Catch-up validation
        if candidate < date {
            guard catchUp || date.timeIntervalSince(candidate) <= 30 else {
                return nil
            }
            let ageInSeconds = date.timeIntervalSince(candidate)
            guard ageInSeconds <= 6 * 3600 else {
                return nil
            }
        }

        return candidate
    }
}

// MARK: - Execution State Model

/// Execution state tracking for `ScheduledRule`.
public struct BGScheduleExecutionState: Codable, Equatable, Sendable {
    public let lastOccurrenceDate: Date?
    public let lastResult: String?
    public let lastExecutionDate: Date?

    public init(
        lastOccurrenceDate: Date? = nil,
        lastResult: String? = nil,
        lastExecutionDate: Date? = nil
    ) {
        self.lastOccurrenceDate = lastOccurrenceDate
        self.lastResult = lastResult
        self.lastExecutionDate = lastExecutionDate
    }
}
