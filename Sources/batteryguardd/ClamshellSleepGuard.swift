import Foundation
import IOKit.pwr_mgt
import BatteryGuardShared

/// Verhindert beim Wachhalten bis zum Ladelimit auch den Deckelschlaf (`SleepDisabled`, nur root).
/// Sicherheitsregeln: nur am Netzteil; zugeklappt ohne Netzteil sofort schlafen; eine Marker-Datei
/// stellt nach einem Absturz den normalen Schlaf wieder her.
final class ClamshellSleepGuard {
    struct Driver {
        var setSleepDisabled: (Bool) -> Bool
        var sleepNow: () -> Void
        var markerExists: () -> Bool
        var setMarker: (Bool) -> Void

        static let markerPath = BGPaths.directory + "/sleep-disabled.marker"

        static var system: Driver {
            Driver(setSleepDisabled: { disabled in
                // Private IOKit-Funktion (IOPMLibPrivate.h); Schlüssel „SleepDisabled“ wie `pmset disablesleep`.
                typealias SetSettingFn = @convention(c) (CFString, CFTypeRef) -> IOReturn
                guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
                      let symbol = dlsym(handle, "IOPMSetSystemPowerSetting") else { return false }
                let set = unsafeBitCast(symbol, to: SetSettingFn.self)
                return set("SleepDisabled" as CFString, (disabled ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef) == kIOReturnSuccess
            }, sleepNow: {
                let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
                guard port != 0 else { return }
                _ = IOPMSleepSystem(port)
                IOServiceClose(port)
            }, markerExists: {
                FileManager.default.fileExists(atPath: markerPath)
            }, setMarker: { present in
                if present {
                    FileManager.default.createFile(atPath: markerPath, contents: Data())
                } else {
                    try? FileManager.default.removeItem(atPath: markerPath)
                }
            })
        }
    }

    private let driver: Driver
    private(set) var isActive = false

    init(driver: Driver = .system) { self.driver = driver }

    /// Beim Dienststart: eine vom letzten Lauf hinterlassene Schlafsperre aufheben.
    func recoverAfterCrash(logger: (String) -> Void) {
        guard driver.markerExists() else { return }
        _ = driver.setSleepDisabled(false)
        driver.setMarker(false)
        logger("Schlafsperre aus einem früheren Lauf aufgehoben.")
    }

    func reconcile(wanted: Bool, pluggedIn: Bool, lidClosed: Bool?, dryRun: Bool, logger: (String) -> Void) {
        if isActive && !pluggedIn && lidClosed == true {
            release(dryRun: dryRun, logger: logger)
            if !dryRun { driver.sleepNow() }
            logger("Zugeklappt ohne Netzteil: Schlafsperre aufgehoben, Mac schläft sofort.")
            return
        }
        let shouldDisable = wanted && pluggedIn
        if shouldDisable && !isActive {
            guard !dryRun else { logger("[DRY-RUN] Schlaf würde auch zugeklappt verhindert"); isActive = true; return }
            if driver.setSleepDisabled(true) {
                driver.setMarker(true)
                isActive = true
                logger("Schlaf bis zum Ladelimit auch zugeklappt verhindert.")
            } else {
                logger("Schlafsperre konnte nicht gesetzt werden.")
            }
        } else if !shouldDisable && isActive {
            release(dryRun: dryRun, logger: logger)
        }
    }

    func release(dryRun: Bool = false, logger: (String) -> Void = { _ in }) {
        guard isActive else { return }
        if !dryRun {
            _ = driver.setSleepDisabled(false)
            driver.setMarker(false)
        }
        isActive = false
        logger("Schlafsperre aufgehoben.")
    }
}
