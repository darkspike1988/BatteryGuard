import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd
@testable import BatteryGuard

struct SleepLedLockTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let limits = [80, 85, 90, 95, 100]

    func battery(_ percent: Int = 70, plugged: Bool = true) -> BatteryInfo {
        var battery = BatteryInfo()
        battery.percent = percent
        battery.pluggedIn = plugged
        return battery
    }

    func decide(_ config: BGConfig, _ battery: BatteryInfo, lock: Bool = true) -> SleepChargePolicy {
        SleepChargePolicy.decide(config: config, battery: battery, hasChargeControl: lock,
                                 systemChargeLimits: limits, now: now)
    }

    @Test func sleepReleasesByDefaultAndInhibitsOnlyWhenOptedIn() {
        var config = BGConfig()
        #expect(decide(config, battery()) == .release)
        config.stopChargingWhenSleeping = true
        #expect(decide(config, battery()) == .inhibitCharging)
        #expect(decide(config, battery(), lock: false) == .release)
        #expect(decide(config, battery(plugged: false)) == .release)
        config.pauseUntil = now.addingTimeInterval(60)
        #expect(decide(config, battery()) == .release)
    }

    @Test func fullChargeRequestsAndObservingModesStillRelease() {
        var config = BGConfig()
        config.stopChargingWhenSleeping = true
        config.chargeToFullOnce = true
        config.fullChargeUntil = now.addingTimeInterval(3600)
        #expect(decide(config, battery()) == .release)
        config = BGConfig()
        config.stopChargingWhenSleeping = true
        config.mode = .native
        #expect(decide(config, battery()) == .release)
    }

    @Test func systemLimitModeHoldsTheNextStepAboveTheCurrentLevel() {
        var config = BGConfig()
        config.stopChargingWhenSleeping = true
        config.mode = .systemLimit
        #expect(decide(config, battery(83), lock: false) == .systemLimit(85))
        #expect(decide(config, battery(40), lock: false) == .systemLimit(80))
        #expect(SleepChargePolicy.decide(config: config, battery: battery(), hasChargeControl: false,
                                         systemChargeLimits: [], now: now) == .release)
    }

    @Test func ledOffWinsAndRoundTrips() throws {
        var config = BGConfig()
        config.magsafeLedOff = true
        config.stopChargingWhenSleeping = true
        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: BGJSON.encoder().encode(config))
        #expect(decoded.magsafeLedOff && decoded.stopChargingWhenSleeping)
        let legacy = try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"magsafeLed":true}"#.utf8))
        #expect(!legacy.magsafeLedOff && !legacy.stopChargingWhenSleeping)
        let merged = config.mergingEdits(since: BGConfig(), into: BGConfig())
        #expect(merged.magsafeLedOff && merged.stopChargingWhenSleeping)
    }

    @MainActor @Test func lidLockOnlyOnClosingWhileKeptAwake() {
        var locks = 0
        let guardian = LidLockGuard(lock: { locks += 1; return true })
        var status = BGStatus()
        status.lidClosed = false
        status.awakeUntilLimitActive = true
        guardian.observe(status, enabled: true)
        status.lidClosed = true
        #expect(guardian.observe(status, enabled: true))
        #expect(!guardian.observe(status, enabled: true)) // bleibt zu: keine zweite Sperre
        status.lidClosed = false
        guardian.observe(status, enabled: true)
        status.lidClosed = true
        status.awakeUntilLimitActive = false
        #expect(!guardian.observe(status, enabled: true))
        status.lidClosed = false
        guardian.observe(status, enabled: false)
        status.lidClosed = true
        status.awakeUntilLimitActive = true
        #expect(!guardian.observe(status, enabled: false))
        #expect(locks == 1)
    }
}
