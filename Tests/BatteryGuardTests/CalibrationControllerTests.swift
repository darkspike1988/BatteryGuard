import Foundation
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct CalibrationControllerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func config(phase: BGCalibrationPhase = .initialCharge) -> BGConfig {
        var c = BGConfig()
        c.calibrationPlan = BGCalibrationPlan(phase: phase, createdAt: now,
            fullHoldStartedAt: phase == .fullHold ? now : nil, previouslyObservedPower: true)
        return c
    }
    func decide(_ c: BGConfig, percent: Int = 70, plugged: Bool = true,
                powerKnown: Bool = true, percentKnown: Bool = true, temperature: Double? = 25,
                previous: ControllerDecision? = nil, verified: Bool = true, allowed: Bool = true,
                date: Date? = nil) -> ControllerDecision {
        var b = BatteryInfo(); b.percent = percent; b.percentAvailable = percentKnown
        b.externalPowerAvailable = powerKnown; b.pluggedIn = plugged; b.temperatureCelsius = temperature
        return ControllerLogic.evaluate(config: c, battery: b, previousDecision: previous,
            hasChargeControl: true, hasDischargeControl: true, allowsAdapterDisconnect: allowed,
            specialHardwareVerified: verified, now: date ?? now)
    }
    @Test func restartContinuesRecordedPhase() throws {
        let initial = config()
        let first = decide(initial, percent: 100)
        #expect(first.state == .discharging)
        var latest = initial
        CalibrationControllerPersistence.apply(snapshot: initial.calibrationPlan!, decision: first, to: &latest)
        let restarted = try BGJSON.decoder().decode(BGConfig.self, from: BGJSON.encoder().encode(latest))
        #expect(decide(restarted).state == .discharging)
        #expect(decide(restarted, percent: 10).updatedCalibrationPlan?.phase == .recharge)
    }
    @Test func mandatoryHeatPausesAndMissingHeatSensorKeepsBlock() {
        let c = config(phase: .discharge)
        let hot = decide(c, temperature: 45)
        #expect(hot.heatProtectionActive && !hot.chargingEnabled && hot.adapterConnected)
        #expect(hot.updatedCalibrationPlan?.phase == .discharge)
        let missing = decide(c, temperature: nil, previous: hot)
        #expect(missing.heatProtectionActive && !missing.chargingEnabled && missing.adapterConnected)
        #expect(c.heatProtectionCelsius == 0)
    }
    @Test func unknownSensorsRestoreAndSoftwareDisconnectCanContinue() {
        let c = config(phase: .discharge)
        #expect(decide(c, powerKnown: false).chargingEnabled)
        #expect(decide(c, percentKnown: false).adapterConnected)
        #expect(decide(c, plugged: false).updatedCalibrationPlan != nil)
        let previous = ControllerDecision(state: .discharging, chargingEnabled: false, adapterConnected: false)
        #expect(!decide(c, plugged: false, previous: previous).adapterConnected)
    }
    @Test func expiryAndMonitorConflictRestore() {
        let c = config(phase: .discharge)
        for d in [decide(c, allowed: false), decide(c, verified: false),
                  decide(c, date: now.addingTimeInterval(BGCalibrationPlan.maxDuration))] {
            #expect(d.adapterConnected && d.chargingEnabled)
            #expect(d.completedCalibrationRequestID == c.calibrationPlan?.requestID)
        }
    }
    @Test func oldCompletionAndPhaseCannotReplaceNewRequest() {
        let old = config(); var latest = config()
        let renewed = latest.calibrationPlan
        CalibrationControllerPersistence.apply(snapshot: old.calibrationPlan!, decision: decide(old, verified: false), to: &latest)
        #expect(latest.calibrationPlan == renewed)
        CalibrationControllerPersistence.apply(snapshot: old.calibrationPlan!, decision: decide(old, percent: 100), to: &latest)
        #expect(latest.calibrationPlan == renewed)
        latest.calibrationPlan = nil
        CalibrationControllerPersistence.apply(snapshot: old.calibrationPlan!, decision: decide(old, percent: 100), to: &latest)
        #expect(latest.calibrationPlan == nil)
    }
    @Test func fullHoldRechargesAfterDip() {
        let c = config(phase: .fullHold)
        let dipped = decide(c, percent: 99)
        #expect(dipped.chargingEnabled && dipped.adapterConnected)
        #expect(dipped.updatedCalibrationPlan?.fullHoldStartedAt == nil)
    }
    @Test func manualReplacementAndScheduleSuppression() throws {
        let c = config()
        let replacement = try BGChargingActionRequest(action: .fullCharge).applying(to: c, at: now)
        #expect(replacement.calibrationPlan == nil)
        var scheduled = c
        scheduled.scheduledTasks = [BGScheduledTask(schedule: try ScheduledRule(name: "Calibration conflict",
            timeZoneIdentifier: "UTC", startsAt: now, recurrence: .once), enabled: true,
            action: BGScheduledAction(kind: .topUp))]
        let context = BGSpecialPlanEvaluationContext(percent: 70, externalPower: .connected,
            canBlockCharging: true, canDisconnectAdapter: true, allowsAdapterDisconnect: true)
        let result = ScheduleRunner.evaluate(config: scheduled, now: now, context: context)
        #expect(result.calibrationPlan == c.calibrationPlan)
        #expect(result.specialChargePlan == nil)
        #expect(result.scheduleHistory.first?.resultString == "skipped: manual override")
    }
    @Test func productionStartRejectedWithoutMutation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        #expect(throws: BGChargingActionError.self) {
            try ConfigServer.apply(BGConfigRequest(action: BGChargingActionRequest(action: .calibration)),
                peerUID: 0, consoleUID: nil, configURL: url)
        }
        #expect(try BGConfigFile.read(at: url).calibrationPlan == nil)
    }
    @Test func terminalCalibrationCarriesMandatoryHeatIntoBaseProfile() {
        var c = config()
        let hot = decide(c, temperature: 45)
        let expired = decide(c, temperature: nil, previous: hot,
            date: now.addingTimeInterval(BGCalibrationPlan.maxDuration))
        #expect(expired.completedCalibrationRequestID != nil)
        #expect(expired.heatProtectionActive && !expired.chargingEnabled && expired.adapterConnected)
        #expect(expired.heatProtectionThresholdCelsius == 40)
        c.calibrationPlan = nil
        let normal = decide(c, temperature: nil, previous: expired,
            date: now.addingTimeInterval(BGCalibrationPlan.maxDuration + 1))
        #expect(normal.heatProtectionActive && !normal.chargingEnabled)
        #expect(normal.heatProtectionThresholdCelsius == 40)
        let cooled = decide(c, temperature: 37, previous: normal,
            date: now.addingTimeInterval(BGCalibrationPlan.maxDuration + 2))
        #expect(!cooled.heatProtectionActive)
        #expect(c.heatProtectionCelsius == 0)
    }

}
