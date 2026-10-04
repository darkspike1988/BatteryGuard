import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct ControllerTests {
    func decision(_ config: BGConfig = BGConfig(), percent: Int = 80,
                  temperature: Double = 25, plugged: Bool = true,
                  previous: ControllerDecision? = nil, chargeControl: Bool = true,
                  adapterDisconnectAllowed: Bool = true) -> ControllerDecision {
        var battery = BatteryInfo()
        battery.percent = percent
        battery.temperatureCelsius = temperature
        battery.pluggedIn = plugged
        return ControllerLogic.evaluate(config: config.sanitized(), battery: battery,
            previousDecision: previous, hasChargeControl: chargeControl, hasDischargeControl: true, allowsAdapterDisconnect: adapterDisconnectAllowed)
    }

    @Test func chargeHysteresis() {
        let hold = decision(percent: 80)
        #expect(!hold.chargingEnabled)
        #expect(!decision(percent: 50, previous: hold).chargingEnabled)
        #expect(decision(percent: 19, previous: hold).chargingEnabled)
    }

    @Test func pendulumHysteresisAndDisabledAdapter() {
        var config = BGConfig(); config.mode = .pendulum
        let off = decision(config, percent: 80)
        #expect(!off.adapterConnected)
        #expect(!decision(config, percent: 77, plugged: false, previous: off).adapterConnected)
        #expect(decision(config, percent: 75, plugged: false, previous: off).adapterConnected)
    }

    @Test func heatProtectionOverridesFullCharge() {
        var config = BGConfig()
        config.chargeToFullOnce = true; config.heatProtectionCelsius = 40
        #expect(!decision(config, percent: 60, temperature: 45).chargingEnabled)
        config.mode = .pendulum
        #expect(!decision(config, percent: 60, temperature: 45).adapterConnected)
        // Pendulum must reconnect at the safety floor instead of draining indefinitely.
        #expect(decision(config, percent: 20, temperature: 45).adapterConnected)
    }

    @Test func chargingResumesAfterCooling() {
        var config = BGConfig(); config.heatProtectionCelsius = 40
        let hot = decision(config, percent: 60, temperature: 45)
        #expect(!hot.chargingEnabled)
        let cooled = decision(config, percent: 60, temperature: 35, previous: hot)
        #expect(cooled.chargingEnabled)
    }

    @Test func disabledAndNativeRestorePower() {
        var config = BGConfig(); config.enabled = false
        let off = ControllerDecision(state: .discharging, chargingEnabled: false, adapterConnected: false)
        #expect(decision(config, previous: off).adapterConnected)
        config.mode = .native
        #expect(decision(config, previous: off).chargingEnabled)
        #expect(decision(config, previous: off).adapterConnected)
    }

    @Test func unsupportedDirectDoesNotDischarge() {
        var config = BGConfig(); config.mode = .direct
        let result = decision(config, percent: 95, chargeControl: false)
        #expect(result.state == .unsupported)
        #expect(result.adapterConnected)
    }

    @Test func fullChargeCompletes() {
        var config = BGConfig(); config.chargeToFullOnce = true
        #expect(!decision(config, percent: 99).resetChargeToFullOnce)
        #expect(decision(config, percent: 100).resetChargeToFullOnce)
    }

    @Test func externalMonitorKeepsPowerInPendulumAndReconnectsPreviouslyDisabledAdapter() {
        var config = BGConfig(); config.upperLimit = 60; config.lowerLimit = 55
        let off = decision(config, percent: 80, chargeControl: false)
        #expect(!off.adapterConnected)
        let desktop = decision(config, percent: 80, plugged: false, previous: off,
                               chargeControl: false, adapterDisconnectAllowed: false)
        #expect(desktop.adapterConnected && desktop.chargingEnabled)
        #expect(desktop.state == .disabled)
        config.mode = .pendulum
        config.heatProtectionCelsius = 40
        #expect(decision(config, percent: 80, temperature: 45,
                         adapterDisconnectAllowed: false).adapterConnected)
        // Unplugging the external display allows ordinary pendulum control again.
        #expect(!decision(config, percent: 80, previous: desktop,
                          chargeControl: false).adapterConnected)
    }

    @Test func externalMonitorPreservesSeparateChargeInhibitionWithoutActiveDischarge() {
        var config = BGConfig(); config.activeDischargeAboveUpper = true
        let result = decision(config, percent: 90, adapterDisconnectAllowed: false)
        #expect(result.adapterConnected)
        #expect(!result.chargingEnabled)
        #expect(result.state == .holding)
        config.heatProtectionCelsius = 40
        #expect(!decision(config, temperature: 45, adapterDisconnectAllowed: false).chargingEnabled)
    }

    @Test func oldConfigAndHostileBounds() throws {
        let old = try BGJSON.decoder().decode(BGConfig.self, from: Data("{}".utf8))
        #expect(old == BGConfig())
        var config = BGConfig()
        config.lowerLimit = Int.max; config.upperLimit = Int.min
        config.heatProtectionCelsius = Int.max
        let clean = config.sanitized()
        #expect(clean.lowerLimit == 15)
        #expect(clean.upperLimit == 20)
        #expect(clean.heatProtectionCelsius == 50)
    }
}
