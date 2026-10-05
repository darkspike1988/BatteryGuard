import Foundation
import IOKit.pwr_mgt
import BatteryGuardShared

/// Prevents user-idle system sleep only. Explicit sleep, display sleep and lid behavior remain OS-owned.
public final class WakeUntilLimitGuard {
    public struct Driver {
        public var create: (TimeInterval) -> UInt32?
        public var release: (UInt32) -> Void
        public init(create: @escaping (TimeInterval) -> UInt32?, release: @escaping (UInt32) -> Void) {
            self.create = create; self.release = release
        }
        public static var system: Driver {
            Driver(create: { timeout in
                var identifier: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithDescription(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    "B-Guard: Wach bis zum Ladelimit" as CFString,
                    "Explicit temporary request; released at charge target or deadline." as CFString,
                    nil, nil, timeout, kIOPMAssertionTimeoutActionRelease as CFString, &identifier)
                return result == kIOReturnSuccess ? identifier : nil
            }, release: { _ = IOPMAssertionRelease($0) })
        }
    }
    private let driver: Driver
    private var assertionID: UInt32?
    private var attemptedDeadline: Date?
    private var lastDeadline: Date?
    public private(set) var message: String?
    public var isActive: Bool { assertionID != nil }

    public init(driver: Driver = .system) { self.driver = driver }
    deinit { release() }

    /// Release also ends this occurrence: wake or a battery percentage dip must not silently restart it.
    public func release() {
        if let assertionID { driver.release(assertionID) }
        assertionID = nil
    }

    public func reconcile(config: BGConfig, battery: BatteryInfo, now: Date, controlSupported: Bool) {
        let deadline = config.awakeUntilLimitUntil
        if deadline != lastDeadline {
            release()
            lastDeadline = deadline
            attemptedDeadline = nil
            message = nil
        }
        guard let deadline else { release(); message = nil; return }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining.isFinite, remaining > 0, remaining <= 2 * 3600,
              now.timeIntervalSince1970.isFinite else { release(); message = nil; return }
        guard controlSupported else {
            release()
            message = "Wach bis zum Limit nicht aktiv: separate Ladesteuerung nicht verfügbar"
            return
        }
        guard config.enabled, config.mode != .native, config.mode != .direct,
              !config.isPaused(at: now), battery.percentAvailable, (0...100).contains(battery.percent),
              battery.externalPowerAvailable, battery.pluggedIn else {
            release(); message = nil; return
        }
        let effective = config.effective(at: now)
        let target = effective.chargeToFullOnce || effective.specialChargePlan?.kind == .topUp ? 100 : effective.upperLimit
        guard battery.percent < target else { release(); message = nil; return }
        guard assertionID == nil, attemptedDeadline != deadline else { return }
        attemptedDeadline = deadline
        assertionID = driver.create(remaining)
        message = assertionID == nil ? "Wach bis zum Limit konnte nicht aktiviert werden" : nil
    }
}
