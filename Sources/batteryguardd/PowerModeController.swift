import Foundation
import BatteryGuardShared

/// Applies the public `pmset` energy modes per power source when the user opted in.
/// macOS switches between the battery and adapter values itself; B-Guard only writes
/// them when the rules change. It deliberately never touches any private SMC key.
final class PowerModeController {
    enum Source: String, CaseIterable, Sendable {
        case battery = "-b", adapter = "-c"
    }

    /// `pmset powermode` values. Without `powermode` support only `.automatic` and `.low` exist.
    enum Level: Int, Sendable {
        case automatic = 0, low = 1, high = 2
    }

    struct Driver {
        var supportsPowerMode: () -> Bool
        var apply: (Source, Level, _ usePowerMode: Bool) -> Bool

        static var system: Driver {
            Driver(supportsPowerMode: {
                guard let output = run(["-g", "custom"]) else { return false }
                return output.split(separator: "\n").contains {
                    $0.trimmingCharacters(in: .whitespaces).hasPrefix("powermode")
                }
            }, apply: { source, level, usePowerMode in
                let arguments = usePowerMode
                    ? [source.rawValue, "powermode", String(level.rawValue)]
                    : [source.rawValue, "lowpowermode", level == .low ? "1" : "0"]
                return run(arguments) != nil
            })
        }

        private static func run(_ arguments: [String]) -> String? {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return String(decoding: data, as: UTF8.self)
            } catch { return nil }
        }
    }

    private let driver: Driver
    private var lastApplied: [Source: Level]?
    private lazy var powerModeSupported: Bool = driver.supportsPowerMode()

    init(driver: Driver = .system) { self.driver = driver }

    var highPowerModeSupported: Bool { powerModeSupported }

    /// Target level per source, or nil when neither rule is active.
    static func desiredLevels(config: BGConfig, highPowerSupported: Bool) -> [Source: Level]? {
        let low = config.lowPowerModeRule, high = config.highPowerModeRule
        guard low != .off || (highPowerSupported && high != .off) else { return nil }
        var levels: [Source: Level] = [:]
        for source in Source.allCases {
            let wantsLow = source == .battery ? low.appliesOnBattery : low.appliesOnAdapter
            let wantsHigh = highPowerSupported && (source == .battery ? high.appliesOnBattery : high.appliesOnAdapter)
            // Low Power Mode wins when both rules claim the same power source.
            levels[source] = wantsLow ? .low : (wantsHigh ? .high : .automatic)
        }
        return levels
    }

    func reconcile(config: BGConfig, dryRun: Bool, logger: (String) -> Void) {
        guard let desired = Self.desiredLevels(config: config, highPowerSupported: powerModeSupported) else {
            if lastApplied != nil {
                let reset = Dictionary(uniqueKeysWithValues: Source.allCases.map { ($0, Level.automatic) })
                if apply(reset, dryRun: dryRun, logger: logger) {
                    logger("Energiemodus auf Automatisch zurückgesetzt (Automatik aus).")
                } else {
                    logger("Energiemodus konnte nicht zurückgesetzt werden.")
                }
                lastApplied = nil
            }
            return
        }
        guard desired != lastApplied else { return }
        if apply(desired, dryRun: dryRun, logger: logger) {
            lastApplied = desired
            logger("Energiemodus gesetzt: Akku \(desired[.battery]!), Netzteil \(desired[.adapter]!).")
        } else {
            logger("Energiemodus konnte nicht umgestellt werden.")
        }
    }

    private func apply(_ levels: [Source: Level], dryRun: Bool, logger: (String) -> Void) -> Bool {
        var success = true
        for source in Source.allCases {
            guard let level = levels[source] else { continue }
            if dryRun {
                let setting = powerModeSupported ? "powermode \(level.rawValue)" : "lowpowermode \(level == .low ? 1 : 0)"
                logger("[DRY-RUN] pmset \(source.rawValue) \(setting)")
            } else if !driver.apply(source, level, powerModeSupported) {
                success = false
            }
        }
        return success
    }
}
