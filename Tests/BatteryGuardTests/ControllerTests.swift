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

    @Test func withoutChargeLockMacOSHoldsTheLimitAndPowerStaysConnected() {
        // No separate charge inhibit: never disconnect the adapter to hold a limit.
        let config = BGConfig()
        for percent in [50, 80, 95] {
            let result = decision(config, percent: percent, chargeControl: false)
            #expect(result.adapterConnected && result.chargingEnabled)
            #expect(result.state == .disabled)
            #expect(result.message == ControllerLogic.nativeLimitMessage)
        }
        // An adapter left disconnected by an older pendulum daemon is reconnected.
        let legacy = ControllerDecision(state: .discharging, chargingEnabled: false, adapterConnected: false)
        #expect(decision(config, percent: 80, plugged: false, previous: legacy, chargeControl: false).adapterConnected)
    }

    @Test func legacyPendulumConfigurationMigratesToAuto() throws {
        let data = Data(#"{"enabled":true,"mode":"pendulum","lowerLimit":75,"upperLimit":80}"#.utf8)
        let config = try BGJSON.decoder().decode(BGConfig.self, from: data)
        #expect(config.mode == .auto && config.upperLimit == 80)
    }

    @Test func heatProtectionOverridesFullCharge() {
        var config = BGConfig()
        config.chargeToFullOnce = true; config.heatProtectionCelsius = 40
        #expect(!decision(config, percent: 60, temperature: 45).chargingEnabled)
        #expect(decision(config, percent: 60, temperature: 45).adapterConnected)
    }

    @Test func chargingResumesAfterCooling() {
        var config = BGConfig(); config.heatProtectionCelsius = 40
        let hot = decision(config, percent: 60, temperature: 45)
        #expect(!hot.chargingEnabled)
        let cooled = decision(config, percent: 60, temperature: 35, previous: hot)
        #expect(cooled.chargingEnabled)
    }

    @Test func heatProtectionHasCoolingHysteresis() {
        for mode in [BGMode.auto] {
            var config = BGConfig(); config.mode = mode; config.heatProtectionCelsius = 40
            let hot = decision(config, percent: 60, temperature: 40.1)
            #expect(hot.heatProtectionActive)
            let threshold = decision(config, percent: 60, temperature: 40, previous: hot)
            #expect(threshold.heatProtectionActive)
            let almostCool = decision(config, percent: 60, temperature: 38.1, previous: threshold)
            #expect(almostCool.heatProtectionActive)
            let cool = decision(config, percent: 60, temperature: 38, previous: almostCool)
            #expect(!cool.heatProtectionActive)
            #expect(cool.adapterConnected && cool.chargingEnabled)
            // Once released, warming below the activation threshold must not reactivate it.
            #expect(!decision(config, percent: 60, temperature: 39.9, previous: cool).heatProtectionActive)
        }
    }

    @Test func sensorLossDoesNotCancelActiveHeatProtection() {
        var config = BGConfig(); config.heatProtectionCelsius = 40
        let hot = decision(config, percent: 60, temperature: 45)
        var battery = BatteryInfo(); battery.percent = 60; battery.pluggedIn = true
        let missing = ControllerLogic.evaluate(config: config, battery: battery, previousDecision: hot,
                                               hasChargeControl: true, hasDischargeControl: true)
        #expect(missing.heatProtectionActive && !missing.chargingEnabled)
        config.heatProtectionCelsius = 0
        #expect(!decision(config, percent: 60, previous: missing).heatProtectionActive)
        // A missing sensor alone must not start a new thermal episode.
        config.heatProtectionCelsius = 40
        #expect(!ControllerLogic.evaluate(config: config, battery: battery, previousDecision: nil,
                                          hasChargeControl: true, hasDischargeControl: true).heatProtectionActive)
    }

    @Test func controlRegisterReadbackRecognizesOnlyKnownLayouts() {
        let layouts: [(String, [UInt8], [UInt8])] = [
            ("CHTE", [0, 0, 0, 0], [1, 0, 0, 0]),
            ("CH0B", [0], [2]), ("CH0C", [0], [2]),
            ("CHIE", [0], [8]), ("CH0J", [0], [1]), ("CH0I", [0], [1])
        ]
        for (key, on, off) in layouts {
            let size = UInt32(on.count)
            #expect(SMCClient.verifyControlRegister(key: key, size: size, bytes: on, expectedEnabled: true) == .matches)
            #expect(SMCClient.verifyControlRegister(key: key, size: size, bytes: off, expectedEnabled: false) == .matches)
            #expect(SMCClient.verifyControlRegister(key: key, size: size, bytes: on, expectedEnabled: false) == .drift)
            #expect(SMCClient.verifyControlRegister(key: key, size: size, bytes: off, expectedEnabled: true) == .drift)
            #expect(SMCClient.verifyControlRegister(key: key, size: size + 1, bytes: on, expectedEnabled: true) == .unavailable)
            #expect(SMCClient.verifyControlRegister(key: key, size: size, bytes: [], expectedEnabled: true) == .unavailable)
            #expect(SMCClient.verifyControlRegister(key: key, size: size, bytes: Array(repeating: 255, count: on.count), expectedEnabled: true) == .unavailable)
        }
        #expect(SMCClient.verifyControlRegister(key: "NEWK", size: 1, bytes: [0], expectedEnabled: true) == .unavailable)
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

    @Test func externalMonitorPreservesSeparateChargeInhibitionWithoutActiveDischarge() {
        var config = BGConfig(); config.activeDischargeAboveUpper = true
        let result = decision(config, percent: 90, adapterDisconnectAllowed: false)
        #expect(result.adapterConnected)
        #expect(!result.chargingEnabled)
        #expect(result.state == .holding)
        config.heatProtectionCelsius = 40
        #expect(!decision(config, temperature: 45, adapterDisconnectAllowed: false).chargingEnabled)
    }

    @Test func batteryPowerDistinguishesZeroMissingAndDischarging() {
        #expect(BatteryReader.batteryPower(voltageMillivolts: 12000, amperageRaw: 0) == 0)
        #expect(BatteryReader.batteryPower(voltageMillivolts: 12000, amperageRaw: 1000) == 12)
        #expect(BatteryReader.batteryPower(voltageMillivolts: 12000,
            amperageRaw: UInt64(UInt32(bitPattern: -1000))) == -12)
        #expect(BatteryReader.batteryPower(voltageMillivolts: nil, amperageRaw: 0) == nil)
        #expect(BatteryReader.batteryPower(voltageMillivolts: .nan, amperageRaw: 0) == nil)
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

    func sleepCharging(_ config: BGConfig = BGConfig(), percent: Int, chargeControl: Bool = true) -> Bool {
        var battery = BatteryInfo()
        battery.percent = percent
        battery.pluggedIn = true
        return ControllerLogic.chargingEnabledDuringSleep(config: config.sanitized(), battery: battery,
            hasChargeControl: chargeControl, now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func sleepKeepsReachedLimitInhibited() {
        // Default 20...80: inside the band the limit stays locked while asleep.
        #expect(!sleepCharging(percent: 80))
        #expect(!sleepCharging(percent: 50))
        // Below the lower limit the Mac may keep charging instead of waking up empty.
        #expect(sleepCharging(percent: 19))
    }

    @Test func sleepFallsBackToNormalChargingForExceptions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(sleepCharging(percent: 80, chargeControl: false))
        var config = BGConfig(); config.mode = .native
        #expect(sleepCharging(config, percent: 80))
        config = BGConfig(); config.enabled = false
        #expect(sleepCharging(config, percent: 80))
        config = BGConfig(); config.pauseUntil = now.addingTimeInterval(600)
        #expect(sleepCharging(config, percent: 80))
        config = BGConfig(); config.chargeToFullOnce = true
        #expect(sleepCharging(config, percent: 80))
        config = BGConfig(); config.travelReadyAt = now.addingTimeInterval(3600)
        #expect(sleepCharging(config, percent: 80))
        config = BGConfig(); config.lowerLimit = 95; config.upperLimit = 100
        #expect(sleepCharging(config, percent: 98))
        var unknown = BatteryInfo(); unknown.percentAvailable = false
        #expect(ControllerLogic.chargingEnabledDuringSleep(config: BGConfig(), battery: unknown,
            hasChargeControl: true, now: now))
    }
}
