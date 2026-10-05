import Testing
import Foundation
@testable import BatteryGuardShared

@Suite("ScheduledRule Tests")
struct ScheduledRuleTests {

    // MARK: - Helper to construct dates in a specific timezone
    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
        timeZoneIdentifier: String = "Europe/Berlin"
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return cal.date(from: comps)!
    }

    // MARK: - Validation & Custom JSON Decoding Tests (invalidzones/names & unknown fields)

    @Test("Validates schedule name constraints and control characters")
    func testNameValidation() {
        let validStart = makeDate(year: 2026, month: 10, day: 5, hour: 22, minute: 0)

        // Valid name up to 60 characters
        let sixtyCharName = String(repeating: "A", count: 60)
        #expect(throws: Never.self) {
            _ = try ScheduledRule(
                name: sixtyCharName,
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }

        // Name exceeding 60 characters must throw
        let sixtyOneCharName = String(repeating: "B", count: 61)
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: sixtyOneCharName,
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }

        // Name with newline control characters must throw
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Night\nSchedule",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }

        // Name with carriage return must throw
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Night\rSchedule",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }

        // Name with tab must throw
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Night\tSchedule",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }

        // Name with null character must throw
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Night\0Schedule",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }
    }

    @Test("Validates time zone identifiers")
    func testTimeZoneValidation() {
        let validStart = makeDate(year: 2026, month: 10, day: 5, hour: 22, minute: 0)

        // Valid zones
        #expect(throws: Never.self) {
            _ = try ScheduledRule(
                name: "Valid Zone Berlin",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: validStart,
                recurrence: .daily
            )
        }
        #expect(throws: Never.self) {
            _ = try ScheduledRule(
                name: "Valid Zone UTC",
                timeZoneIdentifier: "UTC",
                startsAt: validStart,
                recurrence: .daily
            )
        }

        // Invalid zones must throw
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Invalid Zone",
                timeZoneIdentifier: "Mars/Curiosity_Rover",
                startsAt: validStart,
                recurrence: .daily
            )
        }
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Invalid Zone Empty",
                timeZoneIdentifier: "",
                startsAt: validStart,
                recurrence: .daily
            )
        }
    }

    @Test("Validates finite dates and endsAt >= startsAt")
    func testDateRangeValidation() {
        let start = makeDate(year: 2026, month: 10, day: 5, hour: 22, minute: 0)

        // Distant future / past must throw
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Distant Future",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: .distantFuture,
                recurrence: .daily
            )
        }
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Distant Past",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: .distantPast,
                recurrence: .daily
            )
        }

        // endsAt < startsAt must throw
        let earlierEnd = makeDate(year: 2026, month: 10, day: 5, hour: 21, minute: 59)
        #expect(throws: ScheduledRule.ValidationError.self) {
            _ = try ScheduledRule(
                name: "Invalid Range",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: start,
                endsAt: earlierEnd,
                recurrence: .daily
            )
        }

        // endsAt >= startsAt succeeds
        let validEnd = makeDate(year: 2026, month: 10, day: 5, hour: 22, minute: 0)
        #expect(throws: Never.self) {
            _ = try ScheduledRule(
                name: "Valid Range",
                timeZoneIdentifier: "Europe/Berlin",
                startsAt: start,
                endsAt: validEnd,
                recurrence: .daily
            )
        }
    }

    @Test("Custom decode enforces same validation and rejects unknown keys")
    func testCustomDecodeAndUnknownFields() throws {
        let start = makeDate(year: 2026, month: 10, day: 5, hour: 22, minute: 0)
        let rule = try ScheduledRule(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            name: "Normal Schedule",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: start,
            recurrence: .daily
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(rule)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedRule = try decoder.decode(ScheduledRule.self, from: encodedData)
        #expect(decodedRule == rule)

        // Payload with unknown field must be rejected
        let jsonWithUnknownField = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "name": "Normal Schedule",
            "timeZoneIdentifier": "Europe/Berlin",
            "startsAt": "2026-10-05T20:00:00Z",
            "recurrence": "daily",
            "unknownPayloadKey": 12345
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(ScheduledRule.self, from: jsonWithUnknownField)
        }

        // Payload with invalid name (>60 chars) in JSON must be rejected
        let invalidNameJSON = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "name": "\(String(repeating: "X", count: 61))",
            "timeZoneIdentifier": "Europe/Berlin",
            "startsAt": "2026-10-05T20:00:00Z",
            "recurrence": "daily"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(ScheduledRule.self, from: invalidNameJSON)
        }
    }

    // MARK: - Realistic Europe/Berlin DST Tests

    @Test("Europe/Berlin DST spring-forward nonexistent time advances to next legal time")
    func testEuropeBerlinSpringForwardDST() throws {
        // In Europe/Berlin on Sunday, March 29, 2026:
        // Clocks jump from 02:00:00 CET to 03:00:00 CEST. 02:30:00 does not exist.
        let startsAt = makeDate(year: 2026, month: 3, day: 28, hour: 2, minute: 30) // Day before gap
        let rule = try ScheduledRule(
            name: "DST Spring Forward",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: startsAt,
            recurrence: .daily
        )

        // After March 28 02:30, the next occurrence is on March 29.
        guard let next = rule.nextOccurrence(after: startsAt) else {
            Issue.record("Expected next occurrence on DST transition day")
            return
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!

        let day = cal.component(.day, from: next)
        let month = cal.component(.month, from: next)
        let hour = cal.component(.hour, from: next)
        #expect(month == 3)
        #expect(day == 29)
        // Nonexistent time 02:30 must be advanced past the gap (03:00:00 or 03:30:00 depending on resolution policy)
        #expect(hour >= 3)
    }

    @Test("Europe/Berlin DST fall-back repeated hour chooses first occurrence")
    func testEuropeBerlinFallBackDST() throws {
        // In Europe/Berlin on Sunday, October 25, 2026:
        // Clocks fall back from 02:59:59 CEST back to 02:00:00 CET.
        // 02:30:00 occurs twice: first in CEST (UTC+2), then in CET (UTC+1).
        let startsAt = makeDate(year: 2026, month: 10, day: 24, hour: 2, minute: 30) // Day before fall back
        let rule = try ScheduledRule(
            name: "DST Fall Back",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: startsAt,
            recurrence: .daily
        )

        guard let next = rule.nextOccurrence(after: startsAt) else {
            Issue.record("Expected next occurrence on fall back day")
            return
        }

        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "Europe/Berlin")!
        cal.timeZone = tz

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        #expect(comps.year == 2026)
        #expect(comps.month == 10)
        #expect(comps.day == 25)
        #expect(comps.hour == 2)
        #expect(comps.minute == 30)

        // With repeatedTimePolicy: .first, the first occurrence on Oct 25 is in daylight saving time (CEST, +2).
        #expect(tz.isDaylightSavingTime(for: next) == true)
        #expect(tz.secondsFromGMT(for: next) == 7200)
    }

    // MARK: - Monthly 31 Tests

    @Test("Monthly recurrence on 31st skips invalid months without roll-over")
    func testMonthly31SkipsInvalidMonths() throws {
        let jan31 = makeDate(year: 2026, month: 1, day: 31, hour: 20, minute: 0)
        let rule = try ScheduledRule(
            name: "Month End 31st",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: jan31,
            recurrence: .monthly
        )

        // February has 28 days -> skipped! Next occurrence must be March 31!
        let march31Expected = makeDate(year: 2026, month: 3, day: 31, hour: 20, minute: 0)
        let afterJan = rule.nextOccurrence(after: jan31)
        #expect(afterJan == march31Expected)

        // April has 30 days -> skipped! Next occurrence after March 31 must be May 31!
        let may31Expected = makeDate(year: 2026, month: 5, day: 31, hour: 20, minute: 0)
        let afterMarch = rule.nextOccurrence(after: march31Expected)
        #expect(afterMarch == may31Expected)

        // Most recent occurrence on April 15 must be March 31 (since April has no 31)
        let april15 = makeDate(year: 2026, month: 4, day: 15, hour: 12, minute: 0)
        let mostRecentInApril = rule.mostRecentOccurrence(at: april15)
        #expect(mostRecentInApril == march31Expected)
    }

    // MARK: - Leap Day Tests

    @Test("Yearly recurrence on February 29 skips non-leap years")
    func testYearlyFeb29SkipsNonLeapYears() throws {
        // 2024 is a leap year. 2025, 2026, 2027 are non-leap years. 2028 is a leap year.
        let leapDay2024 = makeDate(year: 2024, month: 2, day: 29, hour: 12, minute: 0)
        let rule = try ScheduledRule(
            name: "Leap Day Yearly",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: leapDay2024,
            recurrence: .yearly
        )

        // Next occurrence after 2024-02-29 must skip 2025, 2026, 2027 and land on 2028-02-29
        let leapDay2028Expected = makeDate(year: 2028, month: 2, day: 29, hour: 12, minute: 0)
        let nextFrom2024 = rule.nextOccurrence(after: leapDay2024)
        #expect(nextFrom2024 == leapDay2028Expected)

        // Most recent occurrence from mid-2027 bounded search horizon must be 2024-02-29
        let mid2027 = makeDate(year: 2027, month: 6, day: 1, hour: 10, minute: 0)
        let mostRecent = rule.mostRecentOccurrence(at: mid2027)
        #expect(mostRecent == leapDay2024)
    }

    // MARK: - Biweekly Across DST Tests

    @Test("Biweekly recurrence advances 14 calendar days anchored to local date across DST")
    func testBiweeklyAcrossDST() throws {
        // March 22, 2026 is CET (+1).
        // DST transition happens on March 29, 2026.
        // 14 calendar days after March 22 is April 5, 2026 in CEST (+2).
        let start = makeDate(year: 2026, month: 3, day: 22, hour: 8, minute: 0)
        let rule = try ScheduledRule(
            name: "Biweekly DST",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: start,
            recurrence: .biweekly
        )

        let expected14DaysLater = makeDate(year: 2026, month: 4, day: 5, hour: 8, minute: 0)
        let next = rule.nextOccurrence(after: start)
        #expect(next == expected14DaysLater)

        // Verify wall clock is preserved at 08:00
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let comps = cal.dateComponents([.hour, .minute], from: next!)
        #expect(comps.hour == 8)
        #expect(comps.minute == 0)

        // Most recent occurrence on April 6 must be April 5
        let april6 = makeDate(year: 2026, month: 4, day: 6, hour: 12, minute: 0)
        let recent = rule.mostRecentOccurrence(at: april6)
        #expect(recent == expected14DaysLater)
    }

    // MARK: - Once Recurrence Tests

    @Test("Once recurrence fires exactly once and has no subsequent occurrences")
    func testOnceRecurrence() throws {
        let start = makeDate(year: 2026, month: 6, day: 1, hour: 14, minute: 0)
        let rule = try ScheduledRule(
            name: "Single Run",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: start,
            recurrence: .once
        )

        // Before start returns first legal (start)
        let beforeStart = makeDate(year: 2026, month: 5, day: 1, hour: 0, minute: 0)
        #expect(rule.nextOccurrence(after: beforeStart) == start)

        // At or after start returns nil
        #expect(rule.nextOccurrence(after: start) == nil)

        // Most recent occurrence before start is nil
        #expect(rule.mostRecentOccurrence(at: beforeStart) == nil)

        // Most recent occurrence after start is start
        let afterStart = makeDate(year: 2026, month: 6, day: 2, hour: 0, minute: 0)
        #expect(rule.mostRecentOccurrence(at: afterStart) == start)
    }

    // MARK: - Before Start Returns First Legal Tests

    @Test("Before start date returns first legal occurrence")
    func testBeforeStartReturnsFirstLegal() throws {
        // Weekdays rule starting on a Sunday
        // May 10, 2026 is Sunday. The first legal weekday occurrence is Monday, May 11, 2026.
        let sundayStart = makeDate(year: 2026, month: 5, day: 10, hour: 9, minute: 0)
        let rule = try ScheduledRule(
            name: "Weekday First Legal",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: sundayStart,
            recurrence: .weekdays
        )

        let farBefore = makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0)
        let mondayExpected = makeDate(year: 2026, month: 5, day: 11, hour: 9, minute: 0)
        #expect(rule.nextOccurrence(after: farBefore) == mondayExpected)
    }

    // MARK: - Manual Override Suppression Tests

    @Test("Manual override suppresses while active and suppressed occurrences do not fire after expiry")
    func testManualOverrideSuppression() throws {
        let occDate = makeDate(year: 2026, month: 10, day: 5, hour: 20, minute: 0)
        let rule = try ScheduledRule(
            name: "Suppression Test",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: occDate,
            recurrence: .daily
        )

        let emptyState = BGScheduleExecutionState()

        // 1. While override is active (at 20:30, override until 21:00) -> suppressed
        let duringOverride = makeDate(year: 2026, month: 10, day: 5, hour: 20, minute: 30)
        let overrideUntil = makeDate(year: 2026, month: 10, day: 5, hour: 21, minute: 0)
        let pendingDuring = rule.pendingOccurrence(
            at: duringOverride,
            state: emptyState,
            catchUp: true,
            manualOverrideUntil: overrideUntil
        )
        #expect(pendingDuring == nil)

        // 2. After override has expired (at 21:30, override was until 21:00):
        // The occurrence at 20:00 was scheduled <= overrideUntil (21:00), so it was suppressed!
        // It must NOT execute even after expiry!
        let afterExpiry = makeDate(year: 2026, month: 10, day: 5, hour: 21, minute: 30)
        let pendingAfterExpiry = rule.pendingOccurrence(
            at: afterExpiry,
            state: emptyState,
            catchUp: true,
            manualOverrideUntil: overrideUntil
        )
        #expect(pendingAfterExpiry == nil)

        // 3. Occurrence scheduled AFTER override expired (e.g. override ended at 19:00, occ at 20:00)
        let expiredEarly = makeDate(year: 2026, month: 10, day: 5, hour: 19, minute: 0)
        let pendingValid = rule.pendingOccurrence(
            at: duringOverride,
            state: emptyState,
            catchUp: true,
            manualOverrideUntil: expiredEarly
        )
        #expect(pendingValid == occDate)
    }

    // MARK: - Clock Backward & Duplicate Prevention Tests

    @Test("Clock backward prevents execution and duplicate executions are rejected")
    func testClockBackwardAndDuplicateExecution() throws {
        let occDate = makeDate(year: 2026, month: 10, day: 5, hour: 20, minute: 0)
        let rule = try ScheduledRule(
            name: "Clock Check",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: occDate,
            recurrence: .daily
        )

        // Clock backward check: state was executed at 20:05, but evaluation occurs at 20:01
        let lastExec = makeDate(year: 2026, month: 10, day: 5, hour: 20, minute: 5)
        let backwardNow = makeDate(year: 2026, month: 10, day: 5, hour: 20, minute: 1)
        let backwardState = BGScheduleExecutionState(
            lastOccurrenceDate: nil,
            lastResult: "ok",
            lastExecutionDate: lastExec
        )

        let pendingBackward = rule.pendingOccurrence(
            at: backwardNow,
            state: backwardState,
            catchUp: true,
            manualOverrideUntil: nil
        )
        #expect(pendingBackward == nil)

        // Duplicate execution check: state already recorded this occurrence
        let executedState = BGScheduleExecutionState(
            lastOccurrenceDate: occDate,
            lastResult: "ok",
            lastExecutionDate: occDate
        )
        let pendingDuplicate = rule.pendingOccurrence(
            at: makeDate(year: 2026, month: 10, day: 5, hour: 20, minute: 1),
            state: executedState,
            catchUp: true,
            manualOverrideUntil: nil
        )
        #expect(pendingDuplicate == nil)
    }

    // MARK: - Catch-Up Horizon (<= 6 Hours) Tests

    @Test("Catch-up execution is limited to occurrences within 6 hours")
    func testCatchUpHorizon() throws {
        let occDate = makeDate(year: 2026, month: 10, day: 5, hour: 10, minute: 0)
        let rule = try ScheduledRule(
            name: "Catchup Rule",
            timeZoneIdentifier: "Europe/Berlin",
            startsAt: occDate,
            recurrence: .daily
        )
        let emptyState = BGScheduleExecutionState()

        // 1. Within 6 hours (5 hours late, at 15:00) with catchUp = true -> fires
        let fiveHoursLater = makeDate(year: 2026, month: 10, day: 5, hour: 15, minute: 0)
        let catchUpAllowed = rule.pendingOccurrence(
            at: fiveHoursLater,
            state: emptyState,
            catchUp: true,
            manualOverrideUntil: nil
        )
        #expect(catchUpAllowed == occDate)

        // 2. Within 6 hours with catchUp = false -> does not fire missed occurrence
        let catchUpDisabled = rule.pendingOccurrence(
            at: fiveHoursLater,
            state: emptyState,
            catchUp: false,
            manualOverrideUntil: nil
        )
        #expect(catchUpDisabled == nil)

        // 3. Exceeds 6 hours (6 hours and 1 minute late, at 16:01) -> rejected even with catchUp = true
        let tooLate = makeDate(year: 2026, month: 10, day: 5, hour: 16, minute: 1)
        let expiredCatchUp = rule.pendingOccurrence(
            at: tooLate,
            state: emptyState,
            catchUp: true,
            manualOverrideUntil: nil
        )
        #expect(expiredCatchUp == nil)
    }
}
