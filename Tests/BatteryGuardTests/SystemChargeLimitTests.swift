import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct SystemChargeLimitTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let limits = [80, 85, 90, 95, 100]

    func evaluate(_ config: BGConfig, percent: Int = 70, plugged: Bool = true, temperature: Double = 25,
                  previous: ControllerDecision? = nil, available: [Int]? = nil) -> ControllerDecision {
        var battery = BatteryInfo()
        battery.percent = percent
        battery.pluggedIn = plugged
        battery.temperatureCelsius = temperature
        return ControllerLogic.evaluate(config: config.sanitized(), battery: battery, previousDecision: previous,
            hasChargeControl: false, hasDischargeControl: true, systemChargeLimits: available ?? limits, now: now)
    }

    func systemConfig(upper: Int = 80) -> BGConfig {
        var config = BGConfig()
        config.mode = .systemLimit
        config.lowerLimit = upper - 5
        config.upperLimit = upper
        return config
    }

    @Test func targetRoundsUpToTheNextOfferedStep() {
        #expect(BGSystemChargeLimit.target(for: 60, available: limits) == 80)
        #expect(BGSystemChargeLimit.target(for: 82, available: limits) == 85)
        #expect(BGSystemChargeLimit.target(for: 100, available: limits) == 100)
        #expect(BGSystemChargeLimit.target(for: 90, available: [100, 80, 0, 101]) == 100)
        #expect(BGSystemChargeLimit.target(for: 80, available: []) == nil)
    }

    @Test func limitFollowsProfileWithoutTouchingSMC() {
        let charging = evaluate(systemConfig(upper: 60), percent: 70)
        #expect(charging.systemChargeLimit == 80 && charging.state == .charging)
        #expect(charging.chargingEnabled && charging.adapterConnected)
        let holding = evaluate(systemConfig(upper: 90), percent: 90)
        #expect(holding.systemChargeLimit == 90 && holding.state == .holding)
        #expect(evaluate(systemConfig(), percent: 50, plugged: false).state == .onBattery)
        #expect(evaluate(systemConfig(), percent: 50, plugged: false).systemChargeLimit == 80)
    }

    @Test func disabledPausedAndFullChargeRelease() {
        var config = systemConfig()
        config.enabled = false
        #expect(evaluate(config).systemChargeLimit == 100)
        config = systemConfig()
        config.pauseUntil = now.addingTimeInterval(600)
        #expect(evaluate(config).systemChargeLimit == 100)
        config = systemConfig()
        config.chargeToFullOnce = true
        #expect(evaluate(config).systemChargeLimit == 100)
        #expect(evaluate(config, percent: 100).resetChargeToFullOnce)
    }

    @Test func heatProtectionLowersToTheMinimumStepWithRecovery() {
        var config = systemConfig(upper: 95)
        config.heatProtectionCelsius = 40
        let hot = evaluate(config, percent: 85, temperature: 42)
        #expect(hot.systemChargeLimit == 80 && hot.heatProtectionActive)
        #expect(evaluate(config, percent: 85, temperature: 39, previous: hot).systemChargeLimit == 80)
        #expect(evaluate(config, percent: 85, temperature: 37, previous: hot).systemChargeLimit == 95)
    }

    @Test func topUpUsesFullLimitAndOtherPlansComplete() {
        var config = systemConfig()
        config.specialChargePlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100,
            createdAt: now, expiresAt: now.addingTimeInterval(3600))
        let topUp = evaluate(config, percent: 85)
        #expect(topUp.systemChargeLimit == 100 && topUp.completedSpecialRequestID == nil)

        config.specialChargePlan = BGSpecialChargePlan(kind: .discharge, targetPercent: 60,
            createdAt: now, expiresAt: now.addingTimeInterval(3600))
        let discharge = evaluate(config)
        #expect(discharge.systemChargeLimit == nil)
        #expect(discharge.completedSpecialRequestID == config.specialChargePlan?.requestID)
        #expect(discharge.adapterConnected)
    }

    @Test func unavailableSystemLimitIsUnsupported() {
        let decision = evaluate(systemConfig(), available: [])
        #expect(decision.state == .unsupported && decision.systemChargeLimit == nil)
    }

    @Test func controllerWritesOnlyOfferedChangedValuesAndVerifies() {
        final class Recorder: @unchecked Sendable {
            var current = 80
            var writes: [Int] = []
            var accept = true
        }
        let recorder = Recorder()
        let controller = SystemChargeLimitController(driver: .init(
            availableLimits: { [80, 85, 90, 95, 100] },
            currentLimit: { recorder.current },
            setLimit: { value in
                recorder.writes.append(value)
                if recorder.accept { recorder.current = value }
                return true
            }))
        #expect(controller.apply(80, dryRun: false, logger: nil))
        #expect(recorder.writes.isEmpty)
        #expect(controller.apply(90, dryRun: false, logger: nil))
        #expect(recorder.writes == [90])
        #expect(!controller.apply(70, dryRun: false, logger: nil))
        #expect(controller.apply(95, dryRun: true, logger: nil))
        #expect(recorder.writes == [90])
        recorder.accept = false
        #expect(!controller.apply(100, dryRun: false, logger: nil))
    }

    @Test func unknownModeFromNewerAppIsReadAsObservingAndPathIsReported() throws {
        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"mode":"systemLimit"}"#.utf8))
        #expect(decoded.mode == .systemLimit)
        #expect(BGControlPath(smcKeys: ["CHIE"], mode: .systemLimit, systemLimitAvailable: true) == .systemLimit)
        #expect(BGControlPath(smcKeys: ["CHIE"], mode: .systemLimit, systemLimitAvailable: false) == BGControlPath.none)
    }
}
