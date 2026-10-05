import XCTest
@testable import BatteryGuardShared

final class SpecialChargePlanTests: XCTestCase {

    func testBoundedTargets() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = now.addingTimeInterval(3600)

        // Top-up must target 100%
        let validTopUp = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: expiry)
        XCTAssertTrue(validTopUp.isValid)

        let invalidTopUp = BGSpecialChargePlan(kind: .topUp, targetPercent: 80, createdAt: now, expiresAt: expiry)
        XCTAssertFalse(invalidTopUp.isValid)

        // Discharge must target 10...95
        let validDischargeMin = BGSpecialChargePlan(kind: .discharge, targetPercent: 10, createdAt: now, expiresAt: expiry)
        XCTAssertTrue(validDischargeMin.isValid)

        let validDischargeMax = BGSpecialChargePlan(kind: .discharge, targetPercent: 95, createdAt: now, expiresAt: expiry)
        XCTAssertTrue(validDischargeMax.isValid)

        let invalidDischargeLow = BGSpecialChargePlan(kind: .discharge, targetPercent: 9, createdAt: now, expiresAt: expiry)
        XCTAssertFalse(invalidDischargeLow.isValid)

        let invalidDischargeHigh = BGSpecialChargePlan(kind: .discharge, targetPercent: 96, createdAt: now, expiresAt: expiry)
        XCTAssertFalse(invalidDischargeHigh.isValid)

        // Hold must target 10...95
        let validHold = BGSpecialChargePlan(kind: .hold, targetPercent: 50, createdAt: now, expiresAt: expiry)
        XCTAssertTrue(validHold.isValid)

        let invalidHoldLow = BGSpecialChargePlan(kind: .hold, targetPercent: 5, createdAt: now, expiresAt: expiry)
        XCTAssertFalse(invalidHoldLow.isValid)

        let invalidHoldHigh = BGSpecialChargePlan(kind: .hold, targetPercent: 100, createdAt: now, expiresAt: expiry)
        XCTAssertFalse(invalidHoldHigh.isValid)

        // Action request parameter validation
        XCTAssertThrowsError(try BGChargingActionRequest(action: .topUp, targetPercent: 80).applying(to: BGConfig(), at: now))
        XCTAssertThrowsError(try BGChargingActionRequest(action: .dischargeTo, targetPercent: 5).applying(to: BGConfig(), at: now))
        XCTAssertThrowsError(try BGChargingActionRequest(action: .dischargeTo, targetPercent: 100).applying(to: BGConfig(), at: now))
        XCTAssertThrowsError(try BGChargingActionRequest(action: .holdCharge, targetPercent: 8).applying(to: BGConfig(), at: now))
        XCTAssertThrowsError(try BGChargingActionRequest(action: .holdCharge, targetPercent: nil).applying(to: BGConfig(), at: now))
    }

    func testMalformedDecode() throws {
        // Direct decode of invalid plan throws
        let malformedPlanJSON = """
        {
            "requestID": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "kind": "topUp",
            "targetPercent": 50,
            "createdAt": "2026-10-05T00:00:00Z",
            "expiresAt": "2026-10-05T08:00:00Z",
            "hasObservedPower": false
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BGJSON.decoder().decode(BGSpecialChargePlan.self, from: malformedPlanJSON))

        // BGConfig decode with malformed plan safely drops it to nil
        let malformedConfigJSON = """
        {
            "enabled": true,
            "lowerLimit": 20,
            "upperLimit": 80,
            "specialChargePlan": {
                "requestID": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "kind": "topUp",
                "targetPercent": 50,
                "createdAt": "2026-10-05T00:00:00Z",
                "expiresAt": "2026-10-05T08:00:00Z",
                "hasObservedPower": false
            }
        }
        """.data(using: .utf8)!

        let decodedConfig = try BGJSON.decoder().decode(BGConfig.self, from: malformedConfigJSON)
        XCTAssertNil(decodedConfig.specialChargePlan)

        // Strict sanitization drops invalid plan
        var configWithInvalidPlan = BGConfig()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        configWithInvalidPlan.specialChargePlan = BGSpecialChargePlan(kind: .discharge, targetPercent: 5, createdAt: now, expiresAt: now.addingTimeInterval(3600))
        let sanitized = configWithInvalidPlan.sanitized()
        XCTAssertNil(sanitized.specialChargePlan)
    }

    func testMissingCapabilityAndMonitor() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = now.addingTimeInterval(3600)

        // Hold requires canBlockCharging
        let holdPlan = BGSpecialChargePlan(kind: .hold, targetPercent: 70, createdAt: now, expiresAt: expiry)
        let holdCtxNoBlock = BGSpecialPlanEvaluationContext(
            percent: 70,
            externalPower: .connected,
            canBlockCharging: false,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let holdOutcomeUnavailable = holdPlan.evaluate(context: holdCtxNoBlock, at: now)
        XCTAssertEqual(holdOutcomeUnavailable.state, .unavailable)

        let holdCtxWithBlock = BGSpecialPlanEvaluationContext(
            percent: 70,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: false,
            allowsAdapterDisconnect: false
        )
        let holdOutcomeActive = holdPlan.evaluate(context: holdCtxWithBlock, at: now)
        XCTAssertEqual(holdOutcomeActive.state, .active)

        // Discharge requires canDisconnectAdapter AND allowsAdapterDisconnect
        let dischargePlan = BGSpecialChargePlan(kind: .discharge, targetPercent: 50, createdAt: now, expiresAt: expiry)

        let dischargeCtxNoAdapter = BGSpecialPlanEvaluationContext(
            percent: 80,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: false,
            allowsAdapterDisconnect: true
        )
        XCTAssertEqual(dischargePlan.evaluate(context: dischargeCtxNoAdapter, at: now).state, .unavailable)

        let dischargeCtxNotAllowed = BGSpecialPlanEvaluationContext(
            percent: 80,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: false
        )
        XCTAssertEqual(dischargePlan.evaluate(context: dischargeCtxNotAllowed, at: now).state, .unavailable)

        let dischargeCtxAllowed = BGSpecialPlanEvaluationContext(
            percent: 80,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        XCTAssertEqual(dischargePlan.evaluate(context: dischargeCtxAllowed, at: now).state, .active)
    }

    func testUnknownPowerAndSensor() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = now.addingTimeInterval(3600)

        // Unknown power is never treated as disconnected
        let topUpPlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: expiry, hasObservedPower: true)
        let topUpUnknownPowerCtx = BGSpecialPlanEvaluationContext(
            percent: 100,
            externalPower: .unknown,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let topUpOutcome = topUpPlan.evaluate(context: topUpUnknownPowerCtx, at: now)
        XCTAssertEqual(topUpOutcome.state, .active)
        XCTAssertFalse(topUpOutcome.isComplete)

        // Discharge with unknown power does not complete as known unplug
        let dischargePlan = BGSpecialChargePlan(kind: .discharge, targetPercent: 50, createdAt: now, expiresAt: expiry, hasObservedPower: true)
        let dischargeUnknownPowerCtx = BGSpecialPlanEvaluationContext(
            percent: 80,
            externalPower: .unknown,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let dischargeOutcome = dischargePlan.evaluate(context: dischargeUnknownPowerCtx, at: now)
        XCTAssertEqual(dischargeOutcome.state, .active)
        XCTAssertFalse(dischargeOutcome.isComplete)

        // Nil sensor percent is never treated as 0 or 100
        let dischargeNilPercentCtx = BGSpecialPlanEvaluationContext(
            percent: nil,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let dischargeNilOutcome = dischargePlan.evaluate(context: dischargeNilPercentCtx, at: now)
        XCTAssertEqual(dischargeNilOutcome.state, .unavailable)
        XCTAssertFalse(dischargeNilOutcome.isComplete)
    }

    func testTopUp100UntilDisconnect() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = now.addingTimeInterval(3600)

        // Initial state: cable unplugged, hasObservedPower = false
        var plan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: expiry, hasObservedPower: false)
        let initialCtx = BGSpecialPlanEvaluationContext(
            percent: 80,
            externalPower: .disconnected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let initialOutcome = plan.evaluate(context: initialCtx, at: now)
        XCTAssertEqual(initialOutcome.state, .active)

        // Power plugged in
        let pluggedCtx = BGSpecialPlanEvaluationContext(
            percent: 80,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let pluggedOutcome = plan.evaluate(context: pluggedCtx, at: now)
        XCTAssertEqual(pluggedOutcome.state, .active)
        XCTAssertTrue(pluggedOutcome.updatedPlan?.hasObservedPower == true)
        plan = pluggedOutcome.updatedPlan!

        // Battery reaches 100% while still connected: persists at 100%
        let fullConnectedCtx = BGSpecialPlanEvaluationContext(
            percent: 100,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let fullOutcome = plan.evaluate(context: fullConnectedCtx, at: now)
        XCTAssertEqual(fullOutcome.state, .active)
        XCTAssertFalse(fullOutcome.isComplete)

        // Power disconnected after observed connected: completes!
        let disconnectedCtx = BGSpecialPlanEvaluationContext(
            percent: 100,
            externalPower: .disconnected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let completeOutcome = plan.evaluate(context: disconnectedCtx, at: now)
        XCTAssertEqual(completeOutcome.state, .complete)

        // Ensure BGChargeCompletion old fullcharge logic does NOT clear topUp
        var cfg = BGConfig()
        cfg.specialChargePlan = plan
        cfg.chargeToFullOnce = false
        let snapshot = cfg
        let latest = cfg
        let updated = BGChargeCompletion.applying(snapshot: snapshot, to: latest, at: now)
        XCTAssertNotNil(updated.specialChargePlan)
    }

    func testStaleCompletionPreservingNewUUID() throws {
        var snapshotConfig = BGConfig()
        let oldUUID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = now.addingTimeInterval(3600)
        snapshotConfig.specialChargePlan = BGSpecialChargePlan(
            requestID: oldUUID,
            kind: .topUp,
            targetPercent: 100,
            createdAt: now,
            expiresAt: expiry
        )

        var latestConfig = BGConfig()
        let newUUID = UUID()
        latestConfig.specialChargePlan = BGSpecialChargePlan(
            requestID: newUUID,
            kind: .discharge,
            targetPercent: 60,
            createdAt: now,
            expiresAt: expiry
        )

        // Stale completion with older UUID must preserve newer UUID
        let result = BGChargeCompletion.special(snapshot: snapshotConfig, toLatest: latestConfig)
        XCTAssertEqual(result.specialChargePlan?.requestID, newUUID)

        // Matching UUID is cleared
        let matchedResult = BGChargeCompletion.special(snapshot: latestConfig, toLatest: latestConfig)
        XCTAssertNil(matchedResult.specialChargePlan)
    }

    func testFiniteExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Expiry <= createdAt is invalid
        let expiredPlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: now)
        XCTAssertFalse(expiredPlan.isValid)

        // Expiry > 24 hours is invalid
        let over24hPlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: now.addingTimeInterval(25 * 3600))
        XCTAssertFalse(over24hPlan.isValid)

        // Negative createdAt is invalid
        let negativeTimePlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: Date(timeIntervalSince1970: -100), expiresAt: now)
        XCTAssertFalse(negativeTimePlan.isValid)

        // Non-finite time is invalid
        let nanPlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: Date(timeIntervalSince1970: .nan))
        XCTAssertFalse(nanPlan.isValid)

        // Safe removal on expiration
        let validPlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100, createdAt: now, expiresAt: now.addingTimeInterval(3600))
        XCTAssertTrue(validPlan.isValid)

        var config = BGConfig()
        config.specialChargePlan = validPlan

        let beforeDeadline = config.removingExpiredPlans(at: now.addingTimeInterval(1800))
        XCTAssertNotNil(beforeDeadline.specialChargePlan)

        let afterDeadline = config.removingExpiredPlans(at: now.addingTimeInterval(3601))
        XCTAssertNil(afterDeadline.specialChargePlan)

        // Evaluation after deadline completes
        let ctx = BGSpecialPlanEvaluationContext(
            percent: 50,
            externalPower: .connected,
            canBlockCharging: true,
            canDisconnectAdapter: true,
            allowsAdapterDisconnect: true
        )
        let outcome = validPlan.evaluate(context: ctx, at: now.addingTimeInterval(3601))
        XCTAssertEqual(outcome.state, .complete)
    }

    func testOldConfigDecode() throws {
        let legacyJSON = """
        {
            "enabled": true,
            "lowerLimit": 25,
            "upperLimit": 75,
            "mode": "auto"
        }
        """.data(using: .utf8)!

        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: legacyJSON)
        XCTAssertNil(decoded.specialChargePlan)
        XCTAssertEqual(decoded.lowerLimit, 25)
        XCTAssertEqual(decoded.upperLimit, 75)
    }

    func testP3ActionClearAndPreserveTravel() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var baseConfig = BGConfig()
        baseConfig.pauseUntil = now.addingTimeInterval(1800)
        baseConfig.chargeToFullOnce = true
        baseConfig.fullChargeUntil = now.addingTimeInterval(3600)
        baseConfig.fullChargeRequestID = UUID()

        // Future travel (not yet within 3-hour lead time)
        let futureTravelDate = now.addingTimeInterval(10 * 3600)
        baseConfig.travelReadyAt = futureTravelDate
        let travelUUID = UUID()
        baseConfig.travelRequestID = travelUUID

        let action = BGChargingActionRequest(action: .topUp, minutes: 120)
        let applied = try action.applying(to: baseConfig, at: now)

        // Clears pause, old fullcharge, but preserves future travel
        XCTAssertNil(applied.pauseUntil)
        XCTAssertFalse(applied.chargeToFullOnce)
        XCTAssertNil(applied.fullChargeUntil)
        XCTAssertNil(applied.fullChargeRequestID)
        XCTAssertEqual(applied.travelReadyAt, futureTravelDate)
        XCTAssertEqual(applied.travelRequestID, travelUUID)
        XCTAssertNotNil(applied.specialChargePlan)
        XCTAssertEqual(applied.specialChargePlan?.kind, .topUp)

        // Profile switch cancels special plan
        let profileAction = BGChargingActionRequest(action: .profile, profile: "desk")
        let profiled = try profileAction.applying(to: applied, at: now)
        XCTAssertNil(profiled.specialChargePlan)

        // Disable protection cancels special plan
        let restartSpecial = try action.applying(to: baseConfig, at: now)
        XCTAssertNotNil(restartSpecial.specialChargePlan)
        let disableAction = BGChargingActionRequest(action: .protection, enabled: false)
        let disabled = try disableAction.applying(to: restartSpecial, at: now)
        XCTAssertNil(disabled.specialChargePlan)

        // Cancel special explicitly
        let withSpecial = try action.applying(to: baseConfig, at: now)
        let cancelAction = BGChargingActionRequest(action: .cancelSpecial)
        let canceled = try cancelAction.applying(to: withSpecial, at: now)
        XCTAssertNil(canceled.specialChargePlan)
    }
    func testManualActionsReplaceSpecialWithoutChangingBaseLimits() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var base = BGConfig()
        base.lowerLimit = 75; base.upperLimit = 80
        let special = try BGChargingActionRequest(action: .topUp).applying(to: base, at: now)
        XCTAssertEqual(special.lowerLimit, 75)
        XCTAssertEqual(special.upperLimit, 80)
        XCTAssertTrue(special.effective(at: now).chargeToFullOnce)
        for request in [BGChargingActionRequest(action: .fullCharge),
                        .init(action: .pause, minutes: 60),
                        .init(action: .travel, readyAt: now.addingTimeInterval(3600)),
                        .init(action: .cancelFullCharge)] {
            XCTAssertNil(try request.applying(to: special, at: now).specialChargePlan)
        }
    }

    func testLegacyMergeCannotCreateSpecialOrDeleteRenewedRequest() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = BGConfig()
        let desired = try BGChargingActionRequest(action: .topUp).applying(to: baseline, at: now)
        XCTAssertNil(desired.mergingEdits(since: baseline, into: baseline).specialChargePlan)
        var cancelled = desired
        cancelled.specialChargePlan = nil
        let renewed = try BGChargingActionRequest(action: .topUp).applying(to: desired, at: now)
        XCTAssertEqual(cancelled.mergingEdits(since: desired, into: renewed).specialChargePlan, renewed.specialChargePlan)
        XCTAssertNil(cancelled.mergingEdits(since: desired, into: desired).specialChargePlan)
    }

    func testExpiredPlanCompletesBeforeCapabilityAndMissingSensorFailsClosed() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = BGSpecialChargePlan(kind: .hold, targetPercent: 50,
            createdAt: now.addingTimeInterval(-3600), expiresAt: now)
        let context = BGSpecialPlanEvaluationContext(percent: nil, externalPower: .unknown,
            canBlockCharging: false, canDisconnectAdapter: false, allowsAdapterDisconnect: false)
        XCTAssertTrue(plan.evaluate(context: context, at: now).isComplete)
    }
    func testUnrelatedStaleDisabledEditKeepsConcurrentTopUp() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var baseline = BGConfig(); baseline.enabled = false
        var desired = baseline; desired.magsafeLed = false
        let latest = try BGChargingActionRequest(action: .topUp).applying(to: baseline, at: now)
        let merged = desired.mergingEdits(since: baseline, into: latest)
        XCTAssertEqual(merged.specialChargePlan, latest.specialChargePlan)
        XCTAssertTrue(merged.enabled)
        XCTAssertFalse(merged.magsafeLed)
    }
}
