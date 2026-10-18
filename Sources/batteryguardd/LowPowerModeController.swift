import Foundation
import BatteryGuardShared

/// Applies the public `pmset lowpowermode` setting when the user opted in.
/// It deliberately never touches any private SMC key.
final class LowPowerModeController {
    struct Driver {
        var apply: (Bool) -> Bool
        static var system: Driver {
            Driver { enabled in
                let value = enabled ? "1" : "0"
                for source in ["-b", "-c"] {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                    process.arguments = [source, "lowpowermode", value]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    do {
                        try process.run()
                        process.waitUntilExit()
                        guard process.terminationStatus == 0 else { return false }
                    } catch { return false }
                }
                return true
            }
        }
    }

    private let driver: Driver
    private var lastApplied: Bool?

    init(driver: Driver = .system) { self.driver = driver }

    func reconcile(config: BGConfig, pluggedIn: Bool, dryRun: Bool, logger: (String) -> Void) {
        guard config.lowPowerModeOnBattery else {
            if lastApplied != nil {
                if dryRun {
                    logger("[DRY-RUN] pmset lowpowermode 0 (Automatik aus)")
                } else if driver.apply(false) {
                    logger("Low Power Mode deaktiviert (Automatik aus).")
                } else {
                    logger("Low Power Mode konnte nicht zurückgesetzt werden.")
                }
                lastApplied = nil
            }
            return
        }
        let desired = !pluggedIn
        guard desired != lastApplied else { return }
        if dryRun {
            logger("[DRY-RUN] pmset lowpowermode \(desired ? "1" : "0") (\(desired ? "Akku" : "Netzteil"))")
            lastApplied = desired
            return
        }
        if driver.apply(desired) {
            lastApplied = desired
            logger("Low Power Mode \(desired ? "aktiviert" : "deaktiviert") (\(desired ? "Akku" : "Netzteil")).")
        } else {
            logger("Low Power Mode konnte nicht umgestellt werden.")
        }
    }
}
