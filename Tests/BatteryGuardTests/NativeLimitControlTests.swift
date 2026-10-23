import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

final class FakeNativeLimit: NativeChargeLimitDriving, @unchecked Sendable {
    var isSupported = true
    var applied: [Int] = []
    var released = 0
    var fail = false
    var limit: Int?
    var hasTakenControl: Bool { !applied.isEmpty && released == 0 }
    func currentLimit() -> Int? { limit }
    func apply(_ percent: Int) -> Bool {
        guard !fail else { return false }
        applied.append(percent); limit = percent; released = 0
        return true
    }
    func release() -> Bool { released += 1; limit = 80; return true }
}

struct NativeLimitControlTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func battery(_ percent: Int, plugged: Bool = true, temperature: Double = 25) -> BatteryInfo {
        var b = BatteryInfo()
        b.percent = percent
        b.pluggedIn = plugged
        b.temperatureCelsius = temperature
        return b
    }

    func config(upper: Int = 60, lower: Int = 50, below80: Bool = true) -> BGConfig {
        var c = BGConfig()
        c.upperLimit = upper; c.lowerLimit = lower
        c.controlsNativeLimit = true
        c.nativeLimitBelow80 = below80
        return c.sanitized()
    }

    func ceiling(_ c: BGConfig, _ b: BatteryInfo, previous: ControllerDecision? = nil) -> Int {
        let d = ControllerLogic.evaluate(config: c, battery: b, previousDecision: previous,
                                         hasChargeControl: true, hasDischargeControl: false, now: now)
        return ControllerLogic.nativeCeiling(decision: d, config: c, battery: b, allowBelow80: c.nativeLimitBelow80, now: now)
    }

    @Test func ceilingFollowsTargetAndHysteresis() {
        let c = config()
        #expect(ceiling(c, battery(40)) == 60)
        // Zwischen den Grenzen und nicht ladend: aktuellen Stand halten.
        let hold = ControllerDecision(state: .holding, chargingEnabled: false, adapterConnected: true)
        #expect(ceiling(c, battery(55), previous: hold) == 55)
        // Über dem Ziel ohne aktives Entladen: nicht am Netzteil entladen.
        #expect(ceiling(c, battery(90)) == 90)
        var discharge = c; discharge.activeDischargeAboveUpper = true
        #expect(ceiling(discharge, battery(90)) == 60)
    }

    @Test func ceilingRespectsMacOSMinimumUnlessAllowed() {
        #expect(ceiling(config(below80: false), battery(40)) == 80)
        #expect(ceiling(config(upper: 30, lower: 20), battery(10)) == 30)
    }

    @Test func heatProtectionAndFullChargeMapToTheCeiling() {
        var c = config(); c.heatProtectionCelsius = 35
        #expect(ceiling(c, battery(45, temperature: 40)) == 45)
        var full = config(); full.chargeToFullOnce = true; full.fullChargeUntil = now.addingTimeInterval(3600)
        #expect(ceiling(full, battery(70)) == 100)
    }

    @Test func controllerAppliesOnlyChangesAndReleasesWhenTurnedOff() {
        let smc = SMCClient()
        smc.keys = ["CHIE"]
        let fake = FakeNativeLimit()
        let controller = BatteryController(smc: smc, nativeLimit: fake)
        let c = config()
        _ = controller.step(config: c, battery: battery(40), dryRun: false)
        _ = controller.step(config: c, battery: battery(41), dryRun: false)
        #expect(fake.applied == [60])
        #expect(controller.nativeLimitControlled == 60)
        // Ohne Netzteil wird nichts geschrieben.
        _ = controller.step(config: c, battery: battery(39, plugged: false), dryRun: false)
        #expect(fake.applied == [60])

        var off = c; off.controlsNativeLimit = false
        let decision = controller.step(config: off, battery: battery(45), dryRun: false)
        #expect(fake.released == 1)
        #expect(controller.nativeLimitControlled == nil)
        #expect(decision.message == ControllerLogic.nativeLimitMessage)
    }

    @Test func pauseAndNativeModeHandControlBack() {
        let smc = SMCClient(); smc.keys = ["CHIE"]
        let fake = FakeNativeLimit()
        let controller = BatteryController(smc: smc, nativeLimit: fake)
        _ = controller.step(config: config(), battery: battery(40), dryRun: false)
        var paused = config(); paused.pauseUntil = Date().addingTimeInterval(3600)
        _ = controller.step(config: paused, battery: battery(40), dryRun: false)
        #expect(fake.released == 1)
    }

    @Test func failedWriteIsReportedAndNotRetriedImmediately() {
        let smc = SMCClient(); smc.keys = ["CHIE"]
        let fake = FakeNativeLimit(); fake.fail = true
        let controller = BatteryController(smc: smc, nativeLimit: fake)
        let first = controller.step(config: config(), battery: battery(40), dryRun: false)
        #expect(first.state == .unsupported)
        fake.fail = false
        _ = controller.step(config: config(), battery: battery(40), dryRun: false)
        #expect(fake.applied.isEmpty)
        #expect(controller.nativeLimitControlled == nil)
    }

    @Test func smcChargeLockStillTakesPrecedence() {
        let smc = SMCClient(); smc.keys = ["CHTE", "CHIE"]
        let fake = FakeNativeLimit()
        let controller = BatteryController(smc: smc, nativeLimit: fake)
        _ = controller.step(config: config(), battery: battery(70), dryRun: false)
        #expect(fake.applied.isEmpty)
    }

    @Test func explanationAndEffectivenessShowNativeControl() {
        var status = BGStatus()
        status.percent = 60; status.pluggedIn = true; status.state = .holding
        status.daemonVersion = BGVersion.current; status.updatedAt = now
        status.chargeCapability = BGChargeCapability(keys: ["CHTE": .placeholder, "CHIE": .writable])
        status.nativeLimitControlled = 60
        status.effectiveUpperLimit = 60
        let c = config()
        let reasons = BGChargingExplanation.reasons(config: c, status: status, daemonActive: true, now: now)
        #expect(reasons == [.holdingAtLimit(upper: 60), .bGuardSetsMacOSLimit(limit: 60)])
        let e = BGEffectiveness.evaluate(config: c, status: status, daemonActive: true, daemonCurrent: true, now: now)
        #expect(e.controlPath == .nativeLimit && e.state == .effective && e.appliedUpperLimit == 60)

        status.nativeLimitControlled = nil
        status.nativeLimitSupported = true
        var observer = c; observer.controlsNativeLimit = false
        #expect(BGChargingExplanation.reasons(config: observer, status: status, daemonActive: true, now: now)
            .contains(.canControlMacOSLimit))
        status.macOSChargingToFull = true
        #expect(BGChargingExplanation.reasons(config: observer, status: status, daemonActive: true, now: now)
            .first == .macOSCalibrating)
    }
}
