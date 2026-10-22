import Foundation
import BatteryGuardShared

/// Applies the public `pmset -b lowpowermode` setting when the user opted in.
/// macOS then switches Low Power Mode with the power source by itself, exactly like
/// System Settings → Battery → Low Power Mode → "Only on Battery". The setting for
/// power adapter (`-c`) is never touched, and the previous battery value is restored
/// when the option is turned off. It deliberately never touches any private SMC key.
final class LowPowerModeController {
    struct Driver {
        /// Current battery-power value from `pmset -g custom`, nil if unknown.
        var readBattery: () -> Bool?
        /// Sets `pmset -b lowpowermode`.
        var applyBattery: (Bool) -> Bool
        /// Battery value from before B-Guard changed it; survives daemon restarts.
        var loadSaved: () -> Bool?
        var save: (Bool?) -> Void

        static var system: Driver {
            let stateURL = URL(fileURLWithPath: BGPaths.directory)
                .appendingPathComponent("lowpowermode-before.txt")
            return Driver(
                readBattery: {
                    guard let output = run(["-g", "custom"]) else { return nil }
                    return LowPowerModeController.batteryValue(inCustomSettings: output)
                },
                applyBattery: { run(["-b", "lowpowermode", $0 ? "1" : "0"]) != nil },
                loadSaved: {
                    guard let text = try? String(contentsOf: stateURL, encoding: .utf8) else { return nil }
                    switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    case "1": return true
                    case "0": return false
                    default: return nil
                    }
                },
                save: { value in
                    if let value {
                        try? Data((value ? "1" : "0").utf8).write(to: stateURL, options: .atomic)
                    } else {
                        try? FileManager.default.removeItem(at: stateURL)
                    }
                })
        }

        private static func run(_ arguments: [String]) -> String? {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return String(decoding: data, as: UTF8.self)
            } catch { return nil }
        }
    }

    private let driver: Driver
    private var active = false

    init(driver: Driver = .system) { self.driver = driver }

    /// Parses the "Battery Power:" section of `pmset -g custom`.
    static func batteryValue(inCustomSettings output: String) -> Bool? {
        var inBatterySection = false
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") {
                inBatterySection = trimmed == "Battery Power:"
                continue
            }
            guard inBatterySection else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "lowpowermode" { return fields[1] == "1" }
        }
        return nil
    }

    func reconcile(config: BGConfig, dryRun: Bool, logger: (String) -> Void) {
        if config.lowPowerModeOnBattery {
            guard !active else { return }
            if dryRun {
                logger("[DRY-RUN] pmset -b lowpowermode 1")
                active = true
                return
            }
            let current = driver.readBattery()
            if driver.loadSaved() == nil { driver.save(current ?? false) }
            if current == true {
                active = true
            } else if driver.applyBattery(true) {
                active = true
                logger("Low Power Mode auf Akkubetrieb aktiviert.")
            } else {
                logger("Low Power Mode konnte nicht aktiviert werden.")
            }
            return
        }
        if dryRun {
            if active { logger("[DRY-RUN] pmset -b lowpowermode zurücksetzen") }
            active = false
            return
        }
        active = false
        // Only restore what B-Guard changed; without a saved value nothing is touched.
        guard let previous = driver.loadSaved() else { return }
        if previous || driver.applyBattery(false) {
            driver.save(nil)
            logger("Low Power Mode auf Akkubetrieb zurückgesetzt.")
        } else {
            logger("Low Power Mode konnte nicht zurückgesetzt werden.")
        }
    }
}
