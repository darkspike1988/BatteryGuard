import Foundation
import IOKit.pwr_mgt
import BatteryGuardShared

/// Optional short idle-sleep assertion while the adapter is deliberately disconnected.
/// It never blocks explicit sleep, lid close, or display sleep, and expires after 30 minutes.
final class DischargeSleepGuard {
    struct Driver {
        var create: (TimeInterval) -> UInt32?
        var release: (UInt32) -> Void
        static var system: Driver {
            Driver(create: { timeout in
                var identifier: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithDescription(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    "B-Guard: Aktives Entladen" as CFString,
                    "Optional, time-limited, only while the user requested active discharge." as CFString,
                    nil, nil, timeout, kIOPMAssertionTimeoutActionRelease as CFString, &identifier)
                return result == kIOReturnSuccess ? identifier : nil
            }, release: { _ = IOPMAssertionRelease($0) })
        }
    }

    static let maximumDuration: TimeInterval = 30 * 60

    private let driver: Driver
    private var assertionID: UInt32?
    private var startedAt: Date?

    init(driver: Driver = .system) { self.driver = driver }
    deinit { release() }

    func release() {
        if let assertionID { driver.release(assertionID) }
        assertionID = nil
    }

    func reconcile(config: BGConfig, state: BGChargeState, now: Date, dryRun: Bool) {
        guard config.preventSleepWhileDischarging, state == .discharging else {
            if state != .discharging { startedAt = nil }
            release()
            return
        }
        if startedAt == nil { startedAt = now }
        guard assertionID == nil, let startedAt,
              now.timeIntervalSince(startedAt) < Self.maximumDuration else { return }
        if dryRun { return }
        assertionID = driver.create(Self.maximumDuration)
    }
}
