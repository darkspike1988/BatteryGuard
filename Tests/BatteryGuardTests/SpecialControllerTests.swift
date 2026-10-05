import Foundation
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct SpecialControllerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func config(_ kind: BGSpecialPlanKind = .topUp) -> BGConfig {
        var c = BGConfig()
        c.specialChargePlan = BGSpecialChargePlan(kind: kind, targetPercent: kind == .topUp ? 100 : 60,
            createdAt: now, expiresAt: now.addingTimeInterval(3600))
        return c
    }
    func evaluate(_ c: BGConfig, percent: Int = 70, available: Bool = true, plugged: Bool = true,
                  previous: ControllerDecision? = nil, heat: Double = 25, charge: Bool = true,
                  verified: Bool = false, allowed: Bool = true, date: Date? = nil) -> ControllerDecision {
        var b = BatteryInfo(); b.percent = percent; b.percentAvailable = available
        b.pluggedIn = plugged; b.temperatureCelsius = heat
        return ControllerLogic.evaluate(config: c, battery: b, previousDecision: previous,
            hasChargeControl: charge, hasDischargeControl: true, allowsAdapterDisconnect: allowed,
            specialHardwareVerified: verified, now: date ?? now)
    }
    @Test func topUpHoldsUntilConfirmedUnplug() {
        var c = config()
        let first = evaluate(c, percent: 100)
        #expect(first.state == .holding)
        #expect(!first.resetChargeToFullOnce)
        c.specialChargePlan = first.updatedSpecialPlan
        #expect(evaluate(c, plugged: false).completedSpecialRequestID == c.specialChargePlan?.requestID)
        let off = ControllerDecision(state: .discharging, chargingEnabled: false, adapterConnected: false)
        #expect(evaluate(c, plugged: false, previous: off).completedSpecialRequestID == nil)
    }
    @Test func heatAndFutureTravelRespectSpecial() {
        var c = config(); c.heatProtectionCelsius = 40
        c.travelReadyAt = now.addingTimeInterval(86400)
        let hot = evaluate(c, heat: 45)
        #expect(hot.heatProtectionActive && !hot.chargingEnabled)
        #expect(hot.updatedSpecialPlan != nil)
        #expect(evaluate(c, percent: 85).chargingEnabled)
    }
    @Test func failurePathsRestoreNormal() {
        let c = config()
        for d in [evaluate(c, available: false), evaluate(c, charge: false),
                  evaluate(c, date: now.addingTimeInterval(3600)), evaluate(config(.hold)),
                  evaluate(config(.discharge), verified: true, allowed: false)] {
            #expect(d.chargingEnabled && d.adapterConnected)
            #expect(d.completedSpecialRequestID != nil)
        }
    }
    @Test func renewedRequestSurvivesOldTick() {
        let old = config(); var latest = config()
        let complete = evaluate(old, date: now.addingTimeInterval(3600))
        let renewed = latest.specialChargePlan
        SpecialControllerPersistence.apply(snapshot: old.specialChargePlan!, decision: complete, to: &latest)
        #expect(latest.specialChargePlan == renewed)
        SpecialControllerPersistence.apply(snapshot: old.specialChargePlan!, decision: evaluate(old), to: &latest)
        #expect(latest.specialChargePlan == renewed)
    }
    @Test func verifiedDischargeUsesUnknownSoftwareDisconnect() {
        let c = config(.discharge)
        let off = evaluate(c, verified: true)
        #expect(!off.adapterConnected)
        #expect(evaluate(c, plugged: false, previous: off, verified: true).state == .discharging)
        #expect(evaluate(c, percent: 60, previous: off, verified: true).adapterConnected)
    }
    @Test func atomicInitiationUsesSnapshotAndRejectsUnsupported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        let context = BGSpecialPlanEvaluationContext(percent: 72, externalPower: .connected,
            canBlockCharging: true, canDisconnectAdapter: true, allowsAdapterDisconnect: true)
        let request = BGConfigRequest(action: BGChargingActionRequest(action: .holdCharge, targetPercent: 50))
        let saved = try ConfigServer.apply(request, peerUID: 0, consoleUID: nil, configURL: url,
            specialContext: { context })
        #expect(saved.specialChargePlan?.targetPercent == 72)
        var missing = context; missing.percent = nil
        #expect(throws: BGChargingActionError.self) {
            try ConfigServer.apply(request, peerUID: 0, consoleUID: nil, configURL: url, specialContext: { missing })
        }
        #expect(try BGConfigFile.read(at: url).specialChargePlan?.requestID == saved.specialChargePlan?.requestID)
        var monitor = context; monitor.allowsAdapterDisconnect = false
        #expect(throws: BGChargingActionError.self) {
            try ConfigServer.apply(BGConfigRequest(action: BGChargingActionRequest(action: .dischargeTo, targetPercent: 50)),
                peerUID: 0, consoleUID: nil, configURL: url, specialContext: { monitor })
        }
    }

    @Test func terminalRequestsPreserveHeatAcrossNormalTicks() {
        var c = config(); c.heatProtectionCelsius = 40
        let hot = evaluate(c, heat: 45)
        let expired = evaluate(c, previous: hot, heat: 45, date: now.addingTimeInterval(3600))
        #expect(expired.completedSpecialRequestID != nil)
        #expect(expired.heatProtectionActive && !expired.chargingEnabled && expired.adapterConnected)
        var b = BatteryInfo(); b.percent = 70; b.pluggedIn = true; b.temperatureCelsius = nil
        let unknown = ControllerLogic.evaluate(config: c, battery: b, previousDecision: expired,
            hasChargeControl: true, hasDischargeControl: true, now: now.addingTimeInterval(3601))
        #expect(unknown.heatProtectionActive && !unknown.chargingEnabled)
        c.specialChargePlan = nil
        let normal = ControllerLogic.evaluate(config: c, battery: b, previousDecision: unknown,
            hasChargeControl: true, hasDischargeControl: true, now: now.addingTimeInterval(3602))
        #expect(normal.heatProtectionActive && !normal.chargingEnabled)
        c = config(); c.heatProtectionCelsius = 40; b.percentAvailable = false
        let missing = ControllerLogic.evaluate(config: c, battery: b, previousDecision: hot,
            hasChargeControl: true, hasDischargeControl: true, now: now)
        #expect(missing.completedSpecialRequestID != nil)
        #expect(missing.heatProtectionActive && !missing.chargingEnabled && missing.adapterConnected)
    }

}
