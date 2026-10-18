import Foundation
import Testing
@testable import BatteryGuard

struct BatteryHealthAlertTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func thresholdIsClampedToSupportedRange() {
        #expect(BatteryHealthAlertPolicy.clampThreshold(10) == 50)
        #expect(BatteryHealthAlertPolicy.clampThreshold(80) == 80)
        #expect(BatteryHealthAlertPolicy.clampThreshold(120) == 95)
    }

    @Test func missingOrImplausibleHealthNeverNotifies() {
        #expect(!BatteryHealthAlertPolicy.shouldNotify(healthPercent: nil, threshold: 80, lastSent: nil, now: now))
        #expect(!BatteryHealthAlertPolicy.shouldNotify(healthPercent: 0, threshold: 80, lastSent: nil, now: now))
        #expect(!BatteryHealthAlertPolicy.shouldNotify(healthPercent: 101, threshold: 80, lastSent: nil, now: now))
    }

    @Test func onlyValuesBelowTheThresholdNotify() {
        #expect(BatteryHealthAlertPolicy.shouldNotify(healthPercent: 79, threshold: 80, lastSent: nil, now: now))
        #expect(!BatteryHealthAlertPolicy.shouldNotify(healthPercent: 80, threshold: 80, lastSent: nil, now: now))
        #expect(!BatteryHealthAlertPolicy.shouldNotify(healthPercent: 85, threshold: 80, lastSent: nil, now: now))
    }

    @Test func repeatIsLimitedToThirtyDays() {
        let last = now.addingTimeInterval(-29 * 86400)
        #expect(!BatteryHealthAlertPolicy.shouldNotify(healthPercent: 75, threshold: 80, lastSent: last, now: now))
        let due = now.addingTimeInterval(-30 * 86400)
        #expect(BatteryHealthAlertPolicy.shouldNotify(healthPercent: 75, threshold: 80, lastSent: due, now: now))
    }

    @Test func loweredThresholdDoesNotSuppressAnExistingAlert() {
        let last = now.addingTimeInterval(-40 * 86400)
        #expect(BatteryHealthAlertPolicy.shouldNotify(healthPercent: 74, threshold: 70, lastSent: last, now: now) == false)
        #expect(BatteryHealthAlertPolicy.shouldNotify(healthPercent: 69, threshold: 70, lastSent: last, now: now))
    }
}
