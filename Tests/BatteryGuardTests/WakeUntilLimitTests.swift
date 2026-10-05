import Foundation
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct WakeUntilLimitTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    final class Recorder {
        var timeouts: [Double] = []
        var released: [UInt32] = []
        var fail = false
        var driver: WakeUntilLimitGuard.Driver {
            WakeUntilLimitGuard.Driver(create: { timeout in
                self.timeouts.append(timeout)
                return self.fail ? nil : UInt32(self.timeouts.count)
            }, release: { self.released.append($0) })
        }
    }
    func config() -> BGConfig {
        var c = BGConfig(); c.awakeUntilLimitUntil = now.addingTimeInterval(3600); return c
    }
    func battery(_ percent: Int = 70) -> BatteryInfo {
        var b = BatteryInfo(); b.percent = percent; b.pluggedIn = true; return b
    }
    @Test func createsOnceWithBoundedTimeoutAndReleasesAtTarget() {
        let recorder = Recorder(); let guarder = WakeUntilLimitGuard(driver: recorder.driver)
        let c = config()
        guarder.reconcile(config: c, battery: battery(), now: now, controlSupported: true)
        #expect(guarder.isActive)
        #expect(recorder.timeouts == [3600])
        guarder.reconcile(config: c, battery: battery(), now: now.addingTimeInterval(2), controlSupported: true)
        #expect(recorder.timeouts.count == 1)
        guarder.reconcile(config: c, battery: battery(80), now: now, controlSupported: true)
        #expect(!guarder.isActive && recorder.released == [1])
        guarder.reconcile(config: c, battery: battery(), now: now, controlSupported: true)
        #expect(recorder.timeouts.count == 1)
    }
    @Test func renewalAndExplicitRelease() {
        let recorder = Recorder(); let guarder = WakeUntilLimitGuard(driver: recorder.driver)
        var c = config()
        guarder.reconcile(config: c, battery: battery(), now: now, controlSupported: true)
        c.awakeUntilLimitUntil = now.addingTimeInterval(7200)
        guarder.reconcile(config: c, battery: battery(), now: now, controlSupported: true)
        #expect(recorder.released == [1] && recorder.timeouts == [3600, 7200])
        guarder.release()
        #expect(recorder.released == [1, 2] && !guarder.isActive)
        guarder.reconcile(config: c, battery: battery(), now: now, controlSupported: true)
        #expect(recorder.timeouts.count == 2)
    }
    @Test func failureIsVisibleAndNotRetried() {
        let recorder = Recorder(); recorder.fail = true
        let guarder = WakeUntilLimitGuard(driver: recorder.driver)
        guarder.reconcile(config: config(), battery: battery(), now: now, controlSupported: true)
        #expect(!guarder.isActive && guarder.message != nil)
        guarder.reconcile(config: config(), battery: battery(), now: now, controlSupported: true)
        #expect(recorder.timeouts.count == 1)
    }
    @Test func invalidConditionsNeverCreateAndReleaseExisting() {
        var configs: [BGConfig] = []
        var c = config(); c.enabled = false; configs.append(c)
        c = config(); c.mode = .native; configs.append(c)
        c = config(); c.mode = .direct; configs.append(c)
        c = config(); c.pauseUntil = now.addingTimeInterval(60); configs.append(c)
        c = config(); c.awakeUntilLimitUntil = now; configs.append(c)
        c = config(); c.awakeUntilLimitUntil = now.addingTimeInterval(7201); configs.append(c)
        for invalid in configs {
            let recorder = Recorder(); let guarder = WakeUntilLimitGuard(driver: recorder.driver)
            guarder.reconcile(config: invalid, battery: battery(), now: now, controlSupported: true)
            #expect(recorder.timeouts.isEmpty)
        }
        for flag in 0..<3 {
            let recorder = Recorder(); let guarder = WakeUntilLimitGuard(driver: recorder.driver)
            guarder.reconcile(config: config(), battery: battery(), now: now, controlSupported: true)
            var b = battery()
            if flag == 0 { b.pluggedIn = false }
            if flag == 1 { b.externalPowerAvailable = false }
            if flag == 2 { b.percentAvailable = false }
            guarder.reconcile(config: config(), battery: b, now: now, controlSupported: true)
            #expect(!guarder.isActive && recorder.released == [1])
        }
        let recorder = Recorder(); let guarder = WakeUntilLimitGuard(driver: recorder.driver)
        guarder.reconcile(config: config(), battery: battery(), now: now, controlSupported: false)
        #expect(recorder.timeouts.isEmpty && guarder.message != nil)
    }
    @Test func fullChargeUsesHundredPercent() {
        let recorder = Recorder(); let guarder = WakeUntilLimitGuard(driver: recorder.driver)
        var c = config(); c.chargeToFullOnce = true; c.fullChargeUntil = now.addingTimeInterval(100)
        guarder.reconcile(config: c, battery: battery(90), now: now, controlSupported: true)
        #expect(guarder.isActive)
        guarder.reconcile(config: c, battery: battery(100), now: now, controlSupported: true)
        #expect(!guarder.isActive)
    }
}
