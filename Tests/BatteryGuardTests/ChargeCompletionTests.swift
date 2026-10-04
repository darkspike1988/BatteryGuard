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
        #expect(result.travelReadyAt == nil && result.travelRequestID == nil)
        #expect(result.upperLimit == 90 && result.heatProtectionCelsius == 42)
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
        let merged = renewed.mergingEdits(since: legacy, into: BGConfig())
        #expect(merged.fullChargeRequestID == renewed.fullChargeRequestID && merged.chargeToFullOnce)
        let cleaned = renewed.removingExpiredPlans(at: now.addingTimeInterval(9 * 3600))
        #expect(cleaned.fullChargeRequestID == nil)
        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"chargeToFullOnce":true}"#.utf8))
        #expect(decoded.fullChargeRequestID == nil && decoded.travelRequestID == nil)
    }
}
