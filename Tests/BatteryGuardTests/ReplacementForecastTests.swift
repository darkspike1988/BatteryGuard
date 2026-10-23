import Testing
import Foundation
import BatteryGuardShared

struct ReplacementForecastTests {
    let origin = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86400))

    func days(count: Int, every step: Int = 3, start: Double = 92, perDay: Double, cyclesPerDay: Double = 0.5,
              jitter: [Double] = [0]) -> [BGCapacityDay] {
        (0..<count).map { i in
            let day = origin.addingTimeInterval(Double(i * step) * 86400)
            let value = start + perDay * Double(i * step) + jitter[i % jitter.count]
            return BGCapacityDay(day: day, maximumSource: .rawMaxCapacity, designSource: .designCapacity,
                                 designCapacity: 5000, osVersion: "27.0.0", count: 1, ratioSum: value,
                                 minimum: value, maximum: value, firstSampledAt: day, lastSampledAt: day,
                                 cycleSum: 200 + cyclesPerDay * Double(i * step), cycleSamples: 1)
        }
    }

    @Test func tooLittleDataGivesNoDate() {
        let f = BGReplacementForecast.evaluate(days: days(count: 5, perDay: -0.02), currentCycles: 200,
                                               cycleLimit: 1000, appleCareEnd: nil, limitChange: nil, now: origin)
        #expect(f.status == .insufficientData(daysCollected: 5, spanDays: 12))
        #expect(f.capacityThresholdDate == nil)
    }

    @Test func steadyDeclineProjectsTheEightyPercentDate() throws {
        let data = days(count: 31, perDay: -0.01, jitter: [0.2, -0.2, 0.1, -0.1])
        let now = data.last!.day
        let f = BGReplacementForecast.evaluate(days: data, currentCycles: 245, cycleLimit: 1000,
                                               appleCareEnd: nil, limitChange: nil, now: now)
        #expect(f.status == .declining)
        let perYear = try #require(f.changePerYear)
        #expect(abs(perYear + 3.65) < 0.5)
        let date = try #require(f.capacityThresholdDate)
        let years = date.timeIntervalSince(now) / (365 * 86400)
        #expect(years > 2.5 && years < 3.5)
        let earliest = try #require(f.capacityThresholdEarliest)
        #expect(earliest <= date)
        let cycleDate = try #require(f.cycleLimitDate)
        #expect(abs(cycleDate.timeIntervalSince(now) / 86400 - 1510) < 2)
        #expect(f.cyclesPerDay == 0.5)
    }

    @Test func flatOrRisingCapacityGivesNoDate() {
        let data = days(count: 20, perDay: 0.005)
        let f = BGReplacementForecast.evaluate(days: data, currentCycles: nil, cycleLimit: nil,
                                               appleCareEnd: nil, limitChange: nil, now: data.last!.day)
        #expect(f.status == .noMeasurableDecline)
        #expect(f.capacityThresholdDate == nil)
    }

    @Test func appleCareReminderBeforeCoverageEnds() {
        let data = days(count: 31, start: 82.5, perDay: -0.01)
        let now = data.last!.day
        let soon = now.addingTimeInterval(60 * 86400)
        let f = BGReplacementForecast.evaluate(days: data, currentCycles: nil, cycleLimit: nil,
                                               appleCareEnd: soon, limitChange: nil, now: now)
        #expect(f.appleCareReminderDue)
        let far = BGReplacementForecast.evaluate(days: data, currentCycles: nil, cycleLimit: nil,
                                                 appleCareEnd: now.addingTimeInterval(400 * 86400),
                                                 limitChange: nil, now: now)
        #expect(!far.appleCareReminderDue)
        let healthy = BGReplacementForecast.evaluate(days: days(count: 31, start: 97, perDay: -0.005),
                                                     currentCycles: nil, cycleLimit: nil, appleCareEnd: soon,
                                                     limitChange: nil, now: now)
        #expect(!healthy.appleCareReminderDue)
    }

    @Test func recentLimitChangeIsFlagged() {
        let data = days(count: 31, perDay: -0.01)
        let now = data.last!.day
        let change = BGLimitChange(upperLimit: 60, changedAt: now.addingTimeInterval(-7 * 86400))
        #expect(BGReplacementForecast.evaluate(days: data, currentCycles: nil, cycleLimit: nil,
                                               appleCareEnd: nil, limitChange: change, now: now).settling)
    }
}
