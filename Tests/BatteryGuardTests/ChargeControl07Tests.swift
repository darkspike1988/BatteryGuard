import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct ChargeControl07Tests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let steps = [80, 85, 90, 95, 100]

    func battery(_ percent: Int, plugged: Bool = true, temperature: Double = 25) -> BatteryInfo {
        var battery = BatteryInfo()
        battery.percent = percent
        battery.pluggedIn = plugged
        battery.temperatureCelsius = temperature
        return battery
    }

    func system(upper: Int, lower: Int? = nil, below: Bool = true) -> BGConfig {
        var config = BGConfig()
        config.mode = .systemLimit
        config.upperLimit = upper
        config.lowerLimit = lower ?? upper - 5
        config.allowLimitsBelowSystemMinimum = below
        return config
    }

    func evaluate(_ config: BGConfig, _ battery: BatteryInfo, previous: ControllerDecision? = nil,
                  allowsDisconnect: Bool = true, chargeLock: Bool = false) -> ControllerDecision {
        ControllerLogic.evaluate(config: config.sanitized(), battery: battery, previousDecision: previous,
            hasChargeControl: chargeLock, hasDischargeControl: true, allowsAdapterDisconnect: allowsDisconnect,
            systemChargeLimits: steps, now: now)
    }

    @Test func belowMinimumSetsTheMacOSLimitDirectlyWithoutTheAdapterSwitch() {
        let charging = evaluate(system(upper: 60), battery(50))
        #expect(charging.state == .charging && charging.adapterConnected && charging.systemChargeLimit == 60)
        let hold = evaluate(system(upper: 60), battery(60), previous: charging)
        #expect(hold.state == .holding && hold.adapterConnected && hold.systemChargeLimit == 60)
        // Über dem Ziel entlädt die Firmware am Netzteil; B-Guard trennt das Netzteil nie.
        let above = evaluate(system(upper: 60), battery(75))
        #expect(above.adapterConnected && above.systemChargeLimit == 60)
        #expect(evaluate(system(upper: 20, lower: 10), battery(30)).systemChargeLimit == BGSystemChargeLimit.directMinimum)
    }

    @Test func belowMinimumNeedsOptInAndIgnoresDesktopState() {
        let withoutOptIn = evaluate(system(upper: 60, below: false), battery(70))
        #expect(withoutOptIn.adapterConnected && withoutOptIn.systemChargeLimit == 80 && withoutOptIn.state == .charging)
        // Ohne Netzteil-Schalter gibt es keinen Monitor-/Deckelkonflikt mehr.
        let monitor = evaluate(system(upper: 60), battery(70), allowsDisconnect: false)
        #expect(monitor.adapterConnected && monitor.systemChargeLimit == 60)
        let aboveMinimum = evaluate(system(upper: 90), battery(90))
        #expect(aboveMinimum.adapterConnected && aboveMinimum.systemChargeLimit == 90)
    }

    @Test func heatAndColdHoldTheCurrentLevelThroughTheMacOSLimit() {
        var config = system(upper: 90)
        config.heatProtectionCelsius = 40
        let hot = evaluate(config, battery(70, temperature: 45))
        #expect(hot.heatProtectionActive && hot.adapterConnected && !hot.chargingEnabled && hot.systemChargeLimit == 70)
        // Der gehaltene Wert bleibt stehen, solange es heiß ist.
        #expect(evaluate(config, battery(71, temperature: 45), previous: hot).systemChargeLimit == 70)
        #expect(evaluate(config, battery(65, temperature: 45), previous: hot).systemChargeLimit == 65)
        config.heatProtectionCelsius = 0
        config.coldProtectionCelsius = 5
        let cold = evaluate(config, battery(70, temperature: 2))
        #expect(cold.coldProtectionActive && cold.adapterConnected && cold.systemChargeLimit == 70)
    }

    @Test func withoutDirectValuesHeatStillUsesTheSafetyHold() {
        var config = system(upper: 90, below: false)
        config.heatProtectionCelsius = 40
        let hot = evaluate(config, battery(70, temperature: 45))
        #expect(hot.heatProtectionActive && !hot.adapterConnected && !hot.chargingEnabled && hot.systemChargeLimit == 80)
        let docked = evaluate(config, battery(70, temperature: 45), allowsDisconnect: false)
        #expect(docked.adapterConnected && docked.message?.contains("darunter lädt macOS weiter") == true)
    }

    @Test func directValuesOnlyWithOptIn() {
        final class Fake: @unchecked Sendable { var current = 80; var direct: [Int] = [] }
        let fake = Fake()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bg-mcl-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let controller = SystemChargeLimitController(driver: .init(
            availableLimits: { [80, 85, 90, 95, 100] }, currentLimit: { fake.current },
            setLimit: { fake.current = $0; return true },
            setLimitDirect: { fake.direct.append($0); fake.current = $0; return true }), ownershipPath: path)
        #expect(!controller.apply(60, dryRun: false, logger: nil))
        #expect(controller.apply(60, allowDirect: true, dryRun: false, logger: nil) && fake.direct == [60])
        #expect(controller.apply(85, allowDirect: true, dryRun: false, logger: nil) && fake.direct == [60])
        #expect(!controller.apply(10, allowDirect: true, dryRun: false, logger: nil))
        #expect(controller.restoreOriginal(dryRun: false, logger: nil) && fake.current == 80)
    }

    @Test func limitAndPauseSchedulesRunWithoutChargeControl() throws {
        let limit = BGScheduledAction(kind: .limit, targetPercent: 90)
        #expect(try limit.request().savedProfile?.upperLimit == 90)
        #expect(try BGScheduledAction(kind: .pause, minutes: 120).request() == BGChargingActionRequest(action: .pause, minutes: 120))
        #expect(throws: BGChargingActionError.self) { try BGScheduledAction(kind: .limit, minutes: 5, targetPercent: 90).validate() }
        #expect(throws: BGChargingActionError.self) { try BGScheduledAction(kind: .pause, minutes: 900).validate() }

        var config = BGConfig()
        let rule = try ScheduledRule(id: UUID(), name: "Abends", timeZoneIdentifier: "UTC", startsAt: now, recurrence: .daily)
        config.scheduledTasks = [BGScheduledTask(schedule: rule, enabled: true, catchUp: false, action: limit, state: .init())]
        let context = BGSpecialPlanEvaluationContext(percent: 50, externalPower: .connected, canBlockCharging: false,
                                                     canDisconnectAdapter: false, allowsAdapterDisconnect: true)
        let next = ScheduleRunner.evaluate(config: config, now: now.addingTimeInterval(5), context: context)
        #expect(next.upperLimit == 90 && next.lowerLimit == 85)
    }

    @Test func topUpRespectsHeatProtectionInSystemLimitMode() {
        var config = system(upper: 80, below: false)
        config.heatProtectionCelsius = 40
        config.specialChargePlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100,
            createdAt: now, expiresAt: now.addingTimeInterval(3600))
        let hot = evaluate(config, battery(90, temperature: 45))
        #expect(hot.heatProtectionActive && hot.systemChargeLimit == 80 && hot.completedSpecialRequestID == nil)
        #expect(evaluate(config, battery(90)).systemChargeLimit == 100)
    }

    @Test func holdingBelowMinimumReportsTheRealTarget() {
        let hold = evaluate(system(upper: 60), battery(60))
        #expect(hold.effectiveTargetPercent == 60 && hold.systemChargeLimit == 60)
    }

    @Test func originalSystemLimitIsRestoredWhenLeavingTheMode() {
        final class Fake: @unchecked Sendable { var current = 90 }
        let fake = Fake()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bg-mcl-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let controller = SystemChargeLimitController(driver: .init(availableLimits: { [80, 85, 90, 95, 100] },
            currentLimit: { fake.current }, setLimit: { fake.current = $0; return true }), ownershipPath: path)
        #expect(controller.apply(80, dryRun: false, logger: nil) && fake.current == 80)
        #expect(controller.apply(85, dryRun: false, logger: nil))
        #expect(controller.restoreOriginal(dryRun: false, logger: nil) && fake.current == 90)
        #expect(!FileManager.default.fileExists(atPath: path))
        fake.current = 95
        #expect(controller.restoreOriginal(dryRun: false, logger: nil) && fake.current == 95)
    }

    @Test func coldProtectionBlocksChargingWithHysteresisOnSMC() {
        var config = BGConfig()
        config.coldProtectionCelsius = 5
        let cold = evaluate(config, battery(50, temperature: 3), chargeLock: true)
        #expect(cold.coldProtectionActive && !cold.chargingEnabled && cold.state == .holding)
        #expect(evaluate(config, battery(50, temperature: 6), previous: cold, chargeLock: true).coldProtectionActive)
        #expect(!evaluate(config, battery(50, temperature: 7.5), previous: cold, chargeLock: true).coldProtectionActive)
        #expect(BGConfig.from(json: #"{"coldProtectionCelsius":40}"#).sanitized().coldProtectionCelsius == 15)
    }

    @Test func dischargePlanUsesAnOfferedStepInSystemLimitMode() {
        var config = system(upper: 80, below: false)
        config.specialChargePlan = BGSpecialChargePlan(kind: .discharge, targetPercent: 85,
            createdAt: now, expiresAt: now.addingTimeInterval(3600))
        let running = evaluate(config, battery(95))
        #expect(running.state == .discharging && running.systemChargeLimit == 85 && running.completedSpecialRequestID == nil)
        let done = evaluate(config, battery(85))
        #expect(done.completedSpecialRequestID == config.specialChargePlan?.requestID)
        config.specialChargePlan = BGSpecialChargePlan(kind: .discharge, targetPercent: 70,
            createdAt: now, expiresAt: now.addingTimeInterval(3600))
        #expect(evaluate(config, battery(95)).completedSpecialRequestID != nil)
    }

    @Test func clamshellGuardDisablesSleepOnlyOnAdapterAndSleepsWhenUnplugged() {
        final class Recorder: @unchecked Sendable { var settings: [Bool] = []; var slept = 0; var marker = false }
        let r = Recorder()
        let guardian = ClamshellSleepGuard(driver: .init(
            setSleepDisabled: { r.settings.append($0); return true }, sleepNow: { r.slept += 1 },
            markerExists: { r.marker }, setMarker: { r.marker = $0 }))
        guardian.reconcile(wanted: true, pluggedIn: false, lidClosed: false, dryRun: false, logger: { _ in })
        #expect(r.settings.isEmpty)
        guardian.reconcile(wanted: true, pluggedIn: true, lidClosed: true, dryRun: false, logger: { _ in })
        #expect(r.settings == [true] && r.marker && guardian.isActive)
        guardian.reconcile(wanted: true, pluggedIn: false, lidClosed: true, dryRun: false, logger: { _ in })
        #expect(r.settings == [true, false] && r.slept == 1 && !r.marker && !guardian.isActive)
        // Ziel erreicht bei geschlossenem Deckel: schlafen, außer ein externer Monitor ist angeschlossen.
        guardian.reconcile(wanted: true, pluggedIn: true, lidClosed: true, dryRun: false, logger: { _ in })
        guardian.reconcile(wanted: false, pluggedIn: true, lidClosed: true, externalDisplay: true, dryRun: false, logger: { _ in })
        #expect(r.slept == 1)
        guardian.reconcile(wanted: true, pluggedIn: true, lidClosed: true, dryRun: false, logger: { _ in })
        guardian.reconcile(wanted: false, pluggedIn: true, lidClosed: true, dryRun: false, logger: { _ in })
        #expect(r.slept == 2)
        r.marker = true
        guardian.recoverAfterCrash(logger: { _ in })
        #expect(r.settings.last == false && !r.marker)
    }
}

private extension BGConfig {
    static func from(json: String) -> BGConfig { try! BGJSON.decoder().decode(BGConfig.self, from: Data(json.utf8)) }
}
