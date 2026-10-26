import Foundation
import BatteryGuardShared

/// Sperrt den Bildschirm, wenn der Deckel zugeht, während B-Guard den Mac bis zum Ladelimit wachhält.
/// Ohne Wachhalten schläft der Mac beim Zuklappen ohnehin; dann greift macOS' eigene Sperre.
@MainActor
final class LidLockGuard {
    static let appStorageKey = "bg.lockScreenWhenLidClosed"
    private var wasClosed: Bool?
    private let lock: () -> Bool

    init(lock: @escaping () -> Bool = LidLockGuard.lockScreen) { self.lock = lock }

    /// Returns true when a lock was requested for this lid-closing transition.
    @discardableResult
    func observe(_ status: BGStatus, enabled: Bool) -> Bool {
        let closed = status.lidClosed == true
        defer { wasClosed = closed }
        guard enabled, closed, wasClosed == false, status.awakeUntilLimitActive == true else { return false }
        return lock()
    }

    nonisolated static func lockScreen() -> Bool {
        typealias LockFn = @convention(c) () -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        return unsafeBitCast(symbol, to: LockFn.self)() == 0
    }
}
