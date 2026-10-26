import Foundation
import Testing
import BatteryGuardShared

struct ChargeCompletionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func completedRequestsClearWhileUnrelatedFieldsSurvive() throws {
        var snapshot = try BGChargingActionRequest(action: .fullCharge).applying(to: BGConfig(), at: now)
        snapshot.travelReadyAt = now.addingTimeInterval(3600); snapshot.travelRequestID = UUID()
        var latest = snapshot; latest.upperLimit = 90; latest.heatProtectionCelsius = 42
        let result = BGChargeCompletion.applying(snapshot: snapshot, to: latest, at: now)
        #expect(!result.chargeToFullOnce && result.fullChargeUntil == nil && result.fullChargeRequestID == nil)
        // Reaching 100 % before departure keeps the travel plan holding the battery full.
        #expect(result.travelReadyAt == snapshot.travelReadyAt && result.travelRequestID == snapshot.travelRequestID)
        #expect(result.upperLimit == 90 && result.heatProtectionCelsius == 42)
        let afterDeparture = BGChargeCompletion.applying(snapshot: snapshot, to: latest, at: now.addingTimeInterval(3601))
        #expect(afterDeparture.travelReadyAt == nil && afterDeparture.travelRequestID == nil)
    }

    @Test func cancellingReturnsToNormalWithoutOverridingSchedules() throws {
        var config = try BGChargingActionRequest(action: .fullCharge).applying(to: BGConfig(), at: now)
        #expect(config.manualOverrideUntil != nil)
        config.manualOverrideUntil = nil
        for action in [BGChargingAction.cancelFullCharge, .cancelTravel, .cancelSpecial, .resume] {
            #expect(try BGChargingActionRequest(action: action).applying(to: config, at: now).manualOverrideUntil == nil)
        }
    }

    @Test func legacyMergeCannotCreateUnboundedRequests() {
        let baseline = BGConfig()
        var desired = baseline
        desired.chargeToFullOnce = true // no deadline
        desired.pauseUntil = now.addingTimeInterval(48 * 3600)
        desired.travelReadyAt = now.addingTimeInterval(90 * 86400)
        let merged = desired.mergingEdits(since: baseline, into: baseline, now: now)
        #expect(!merged.chargeToFullOnce && merged.pauseUntil == nil && merged.travelReadyAt == nil)
        desired.chargeToFullOnce = true; desired.fullChargeUntil = now.addingTimeInterval(3600)
        desired.pauseUntil = now.addingTimeInterval(3600)
        #expect(desired.mergingEdits(since: baseline, into: baseline, now: now).chargeToFullOnce)
        #expect(desired.mergingEdits(since: baseline, into: baseline, now: now).pauseUntil != nil)
    }

    @Test func holdTargetIsClampedToAllowedRange() {
        #expect(BGChargingActionRequest.holdTarget(forCurrentPercent: 100) == 95)
        #expect(BGChargingActionRequest.holdTarget(forCurrentPercent: 5) == 10)
        #expect(BGChargingActionRequest.holdTarget(forCurrentPercent: 63) == 63)
    }

    @Test func fullChargeDaysUseTheLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var s = BGStatus(); s.percent = 100; s.state = .holding; s.pluggedIn = true
        // 16:30 and 17:30 local time on one day straddle UTC midnight in summer.
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 16, minute: 30)))
        let samples = [0.0, 3600].map { offset -> BGHistorySample in
            s.updatedAt = start.addingTimeInterval(offset); return BGHistorySample(status: s)
        }
        let report = BGHistory.weeklyReport(samples, now: start.addingTimeInterval(7200), calendar: calendar)
        #expect(report.fullChargeDays == 1)
    }

    @Test func renewedRequestsAtIdenticalDatesSurviveJSONAndOldCompletion() throws {
        let action = BGChargingActionRequest(action: .fullCharge)
        let snapshot = try action.applying(to: BGConfig(), at: now)
        let renewed = try action.applying(to: snapshot, at: now)
        #expect(snapshot.fullChargeUntil == renewed.fullChargeUntil)
        #expect(snapshot.fullChargeRequestID != renewed.fullChargeRequestID)
        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: BGJSON.encoder().encode(renewed))
        #expect(BGChargeCompletion.applying(snapshot: snapshot, to: decoded, at: now) == decoded)
        let travel = BGChargingActionRequest(action: .travel, readyAt: now.addingTimeInterval(3600))
        let oldTravel = try travel.applying(to: BGConfig(), at: now)
        let newTravel = try travel.applying(to: oldTravel, at: now)
        #expect(oldTravel.travelReadyAt == newTravel.travelReadyAt)
        #expect(oldTravel.travelRequestID != newTravel.travelRequestID)
        #expect(BGChargeCompletion.applying(snapshot: oldTravel, to: newTravel, at: now) == newTravel)
    }

    @Test func newDeadlinesAndNewActiveOrFutureTravelSurvive() throws {
        var snapshot = BGConfig(); snapshot.chargeToFullOnce = true; snapshot.fullChargeUntil = now.addingTimeInterval(100)
        for delta in [3600.0, 86400.0] {
            var latest = snapshot; latest.fullChargeUntil = now.addingTimeInterval(200)
            latest.travelReadyAt = now.addingTimeInterval(delta)
            #expect(BGChargeCompletion.applying(snapshot: snapshot, to: latest, at: now) == latest)
        }
        var oldTravel = snapshot; oldTravel.travelReadyAt = now.addingTimeInterval(60)
        var latest = oldTravel; latest.travelReadyAt = now.addingTimeInterval(120)
        let result = BGChargeCompletion.applying(snapshot: oldTravel, to: latest, at: now)
        #expect(result.travelReadyAt == latest.travelReadyAt)
        #expect(!result.chargeToFullOnce)
    }

    @Test func legacyConfigCompletesAndNewIDsMergeAsLogicalRequests() throws {
        var legacy = BGConfig(); legacy.chargeToFullOnce = true
        #expect(!BGChargeCompletion.applying(snapshot: legacy, to: legacy, at: now).chargeToFullOnce)
        let renewed = try BGChargingActionRequest(action: .fullCharge).applying(to: legacy, at: now)
        let merged = renewed.mergingEdits(since: legacy, into: BGConfig(), now: now)
        #expect(merged.fullChargeRequestID == renewed.fullChargeRequestID && merged.chargeToFullOnce)
        let cleaned = renewed.removingExpiredPlans(at: now.addingTimeInterval(9 * 3600))
        #expect(cleaned.fullChargeRequestID == nil)
        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"chargeToFullOnce":true}"#.utf8))
        #expect(decoded.fullChargeRequestID == nil && decoded.travelRequestID == nil)
    }
}
