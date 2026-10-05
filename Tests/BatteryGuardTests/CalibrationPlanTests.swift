import Foundation
import XCTest
@testable import BatteryGuardShared

final class CalibrationPlanTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContext(
        percent: Int? = 80,
        externalPower: BGExternalPowerState = .connected,
        temperatureCelsius: Double? = 30.0,
        heatThreshold: Int = 45,
        heatActive: Bool = false,
        hardwareVerified: Bool = true,
        adapterDisabledByUs: Bool = false
    ) -> BGCalibrationContext {
        BGCalibrationContext(
            percent: percent,
            externalPower: externalPower,
            temperatureCelsius: temperatureCelsius,
            heatThreshold: heatThreshold,
            heatActive: heatActive,
            hardwareVerified: hardwareVerified,
            adapterDisabledByUs: adapterDisabledByUs
        )
    }

    // MARK: - 1..8: Phase Transitions & Simulated Time

    func testInitialChargeActiveUnder100() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(percent: 90)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(60))

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .initialCharge)
            XCTAssertEqual(cmd, .charge)
        } else {
            XCTFail("Expected active .charge, got \(outcome)")
        }
    }

    func testInitialChargeAdvancesToDischargeAt100() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(percent: 100)
        let advanceDate = baseDate.addingTimeInterval(300)
        let outcome = plan.evaluate(context: ctx, at: advanceDate)

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .discharge)
            XCTAssertEqual(updated.phaseStartedAt, advanceDate)
            XCTAssertEqual(cmd, .discharge)
        } else {
            XCTFail("Expected active .discharge, got \(outcome)")
        }
    }

    func testDischargeActiveAbove10() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .discharge
        plan.phaseStartedAt = baseDate
        let ctx = makeContext(percent: 50)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(600))

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .discharge)
            XCTAssertEqual(cmd, .discharge)
        } else {
            XCTFail("Expected active .discharge, got \(outcome)")
        }
    }

    func testDischargeAdvancesToRechargeAt10OrBelow() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .discharge
        plan.phaseStartedAt = baseDate
        let ctx = makeContext(percent: 10)
        let rechargeDate = baseDate.addingTimeInterval(1200)
        let outcome = plan.evaluate(context: ctx, at: rechargeDate)

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .recharge)
            XCTAssertEqual(updated.phaseStartedAt, rechargeDate)
            XCTAssertEqual(cmd, .charge)
        } else {
            XCTFail("Expected active .charge in recharge, got \(outcome)")
        }
    }

    func testRechargeActiveUnder100() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .recharge
        plan.phaseStartedAt = baseDate
        let ctx = makeContext(percent: 95)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(600))

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .recharge)
            XCTAssertEqual(cmd, .charge)
        } else {
            XCTFail("Expected active .charge, got \(outcome)")
        }
    }

    func testRechargeEntersFullHoldAt100() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .recharge
        plan.phaseStartedAt = baseDate
        let ctx = makeContext(percent: 100)
        let holdDate = baseDate.addingTimeInterval(1800)
        let outcome = plan.evaluate(context: ctx, at: holdDate)

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .fullHold)
            XCTAssertEqual(updated.phaseStartedAt, holdDate)
            XCTAssertEqual(updated.fullHoldStartedAt, holdDate)
            XCTAssertEqual(cmd, .hold)
        } else {
            XCTFail("Expected active .hold, got \(outcome)")
        }
    }

    func testFullHoldActiveUnder1Hour() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .fullHold
        plan.phaseStartedAt = baseDate
        plan.fullHoldStartedAt = baseDate
        let ctx = makeContext(percent: 100)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(1800))

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .fullHold)
            XCTAssertEqual(cmd, .hold)
        } else {
            XCTFail("Expected active .hold, got \(outcome)")
        }
    }

    func testFullHoldCompletesAfter1HourContinuous() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .fullHold
        plan.phaseStartedAt = baseDate
        plan.fullHoldStartedAt = baseDate
        let ctx = makeContext(percent: 100)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(3600))

        if case .complete(let reason) = outcome {
            XCTAssertTrue(reason.contains("1 hour"))
        } else {
            XCTFail("Expected complete outcome, got \(outcome)")
        }
    }

    // MARK: - 9..15: Expiry, Sensors & Power Constraints

    func testExpiryReturnsComplete() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate, duration: 3600)
        let ctx = makeContext()
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(3601))

        if case .complete(let reason) = outcome {
            XCTAssertTrue(reason.contains("expired"))
        } else {
            XCTFail("Expected expired complete outcome, got \(outcome)")
        }
    }

    func testUnknownPercentPauses() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(percent: nil)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("percentage"))
        } else {
            XCTFail("Expected paused for unknown percent, got \(outcome)")
        }
    }

    func testPowerDisconnectedPausesAwaitingConnect() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(externalPower: .disconnected)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("disconnected"))
        } else {
            XCTFail("Expected paused for disconnected power, got \(outcome)")
        }
    }

    func testMissingPowerPausesNormalRestore() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(externalPower: .unknown)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("unknown"))
        } else {
            XCTFail("Expected paused for missing power in initial charge, got \(outcome)")
        }
    }

    func testPowerUnknownAllowedSolelyInDischargeWithAdapterDisabledAndObservedPower() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .discharge
        plan.phaseStartedAt = baseDate
        plan.previouslyObservedPower = true
        let ctx = makeContext(percent: 50, externalPower: .unknown, adapterDisabledByUs: true)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(60))

        if case .active(let updated, let cmd) = outcome {
            XCTAssertEqual(updated.phase, .discharge)
            XCTAssertEqual(cmd, .discharge)
        } else {
            XCTFail("Expected active .discharge when adapter disabled by us with observed power, got \(outcome)")
        }
    }

    func testPowerUnknownDischargeDisallowedWithoutAdapterDisabled() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .discharge
        plan.phaseStartedAt = baseDate
        plan.previouslyObservedPower = true
        let ctx = makeContext(percent: 50, externalPower: .unknown, adapterDisabledByUs: false)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(60))

        if case .paused = outcome {
            // expected
        } else {
            XCTFail("Expected paused without adapterDisabledByUs, got \(outcome)")
        }
    }

    func testPowerUnknownDischargeDisallowedWithoutPreviouslyObservedPower() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .discharge
        plan.phaseStartedAt = baseDate
        plan.previouslyObservedPower = false
        let ctx = makeContext(percent: 50, externalPower: .unknown, adapterDisabledByUs: true)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(60))

        if case .paused = outcome {
            // expected
        } else {
            XCTFail("Expected paused without previouslyObservedPower, got \(outcome)")
        }
    }

    // MARK: - 16..19: Heat & Conservative FullHold Timer Resets

    func testHeatActivePauses() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(heatActive: true)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("Heat"))
        } else {
            XCTFail("Expected paused for heat active, got \(outcome)")
        }
    }

    func testTemperatureExceedingThresholdPauses() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(temperatureCelsius: 46.0, heatThreshold: 45)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("threshold"))
        } else {
            XCTFail("Expected paused for temperature over threshold, got \(outcome)")
        }
    }

    func testMissingTempAfterHeatActiveStaysPaused() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(temperatureCelsius: nil, heatActive: true)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("Temperature"))
        } else {
            XCTFail("Expected paused when temperature missing after heatActive, got \(outcome)")
        }
    }

    func testHeatPauseResetsFullHoldTimerConservatively() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .fullHold
        plan.phaseStartedAt = baseDate
        plan.fullHoldStartedAt = baseDate
        let ctx = makeContext(percent: 100, heatActive: true)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(1200))

        if case .paused(let updated, _) = outcome {
            XCTAssertNil(updated.fullHoldStartedAt, "Conservative reset requires fullHoldStartedAt to be reset to nil")
        } else {
            XCTFail("Expected paused resetting fullHoldStartedAt, got \(outcome)")
        }
    }

    // MARK: - 20..24: Clock Backward, Unverified Backend, UUID & Strict Decode

    func testClockBackwardPauses() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phaseStartedAt = baseDate.addingTimeInterval(100)
        let ctx = makeContext()
        let outcome = plan.evaluate(context: ctx, at: baseDate)

        if case .paused(_, let reason) = outcome {
            XCTAssertTrue(reason.contains("Clock moved backward"))
        } else {
            XCTFail("Expected paused for clock backward, got \(outcome)")
        }
    }

    func testFullHoldClockBackwardNeverCredits() {
        var plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        plan.phase = .fullHold
        plan.phaseStartedAt = baseDate
        plan.fullHoldStartedAt = baseDate.addingTimeInterval(500)
        let ctx = makeContext(percent: 100)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(400))

        if case .paused(let updated, _) = outcome {
            XCTAssertNil(updated.fullHoldStartedAt, "Clock backward must never credit and conservatively reset hold")
        } else {
            XCTFail("Expected paused resetting full hold timestamp, got \(outcome)")
        }
    }

    func testUnverifiedHardwareReturnsUnavailable() {
        let plan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let ctx = makeContext(hardwareVerified: false)
        let outcome = plan.evaluate(context: ctx, at: baseDate.addingTimeInterval(10))

        if case .unavailable(let reason) = outcome {
            XCTAssertTrue(reason.contains("Hardware backend unverified"))
        } else {
            XCTFail("Expected unavailable for unverified backend, got \(outcome)")
        }
    }

    func testOldUUIDProtectsRenewedRequests() {
        let oldPlan = BGCalibrationPlan.manuallyStarted(requestID: UUID(), at: baseDate)
        let newRequestID = UUID()

        XCTAssertFalse(oldPlan.matches(requestID: newRequestID))
        XCTAssertFalse(BGCalibrationPlan.isLatestIdentity(plan: oldPlan, expectedRequestID: newRequestID))
    }

    func testStrictDecodeRejectsUnknownFieldsAndInvalidInvariants() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let validPlan = BGCalibrationPlan.manuallyStarted(at: baseDate)
        let validData = try encoder.encode(validPlan)

        var jsonObject = try JSONSerialization.jsonObject(with: validData) as! [String: Any]
        jsonObject["unexpectedField"] = "attack"
        let tamperedData = try JSONSerialization.data(withJSONObject: jsonObject)

        XCTAssertThrowsError(try decoder.decode(BGCalibrationPlan.self, from: tamperedData), "Must reject unknown fields")

        // Max 72h invariant rejection
        let invalidMax72h = BGCalibrationPlan(
            createdAt: baseDate,
            expiresAt: baseDate.addingTimeInterval(72 * 3600 + 500)
        )
        // If constructed via raw fields where duration > 72h
        let rawInvalidExpiryJSON = """
        {
            "requestID": "\(UUID().uuidString)",
            "phase": "initialCharge",
            "createdAt": \(baseDate.timeIntervalSinceReferenceDate),
            "expiresAt": \(baseDate.addingTimeInterval(73 * 3600).timeIntervalSinceReferenceDate),
            "phaseStartedAt": \(baseDate.timeIntervalSinceReferenceDate),
            "previouslyObservedPower": false
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(BGCalibrationPlan.self, from: rawInvalidExpiryJSON))
    }
    func testPausedFullHoldRoundTripAndDipRestartsHour() throws {
        var plan = BGCalibrationPlan(createdAt: baseDate)
        plan.phase = .fullHold
        plan.phaseStartedAt = baseDate
        plan.fullHoldStartedAt = baseDate
        guard case .paused(let paused, _) = plan.evaluate(context: makeContext(temperatureCelsius: 45, heatActive: true), at: baseDate.addingTimeInterval(100)) else {
            return XCTFail("Expected thermal pause")
        }
        let decoded = try BGJSON.decoder().decode(BGCalibrationPlan.self, from: BGJSON.encoder().encode(paused))
        XCTAssertNil(decoded.fullHoldStartedAt)
        guard case .active(let dipped, let command) = decoded.evaluate(context: makeContext(percent: 99), at: baseDate.addingTimeInterval(4000)) else {
            return XCTFail("Dip must recharge rather than complete")
        }
        XCTAssertEqual(command, .charge)
        XCTAssertNil(dipped.fullHoldStartedAt)
    }

    func testMissingTemperaturePausesBeforePhaseTransition() {
        let plan = BGCalibrationPlan(createdAt: baseDate)
        guard case .paused(let updated, _) = plan.evaluate(context: makeContext(percent: 100, temperatureCelsius: nil), at: baseDate) else {
            return XCTFail("Missing temperature must pause")
        }
        XCTAssertEqual(updated.phase, .initialCharge)
    }
}
