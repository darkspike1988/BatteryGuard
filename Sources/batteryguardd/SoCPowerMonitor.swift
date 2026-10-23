import Foundation
import BatteryGuardShared

/// Misst die SoC-Leistung mit Apples `powermetrics` (benötigt root) im Hintergrund.
/// Der Regeltakt liest nur den letzten Wert und wartet nie auf eine Messung.
final class SoCPowerMonitor: @unchecked Sendable {
    static let interval: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.batteryguard.socpower", qos: .utility)
    private let lock = NSLock()
    private var latestValue: BGSoCPower?
    private var running = false
    private var lastStart: Date?
    private let measure: () -> Data?

    init(measure: @escaping () -> Data? = SoCPowerMonitor.runPowermetrics) {
        self.measure = measure
    }

    var latest: BGSoCPower? {
        lock.lock(); defer { lock.unlock() }
        return latestValue
    }

    /// Startet höchstens alle 30 Sekunden eine Messung; laufende Messungen werden nicht verdoppelt.
    func refreshIfDue(now: Date = Date()) {
        lock.lock()
        guard !running, lastStart.map({ now.timeIntervalSince($0) >= Self.interval }) ?? true else {
            lock.unlock(); return
        }
        running = true
        lastStart = now
        lock.unlock()
        queue.async { [self] in
            let value = measure().flatMap { Self.parse($0, sampledAt: Date()) }
            lock.lock()
            latestValue = value
            running = false
            lock.unlock()
        }
    }

    static func runPowermetrics() -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["-n", "1", "-i", "1000", "-s", "cpu_power,gpu_power,ane_power", "-f", "plist"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch { return nil }
    }

    /// powermetrics trennt Plist-Datensätze mit NUL und meldet Leistung in Milliwatt.
    static func parse(_ data: Data, sampledAt: Date) -> BGSoCPower? {
        let cleaned = Data(data.filter { $0 != 0 })
        guard let plist = try? PropertyListSerialization.propertyList(from: cleaned, format: nil) as? [String: Any],
              let processor = plist["processor"] as? [String: Any] else { return nil }
        func watts(_ key: String) -> Double? { (processor[key] as? NSNumber).map { $0.doubleValue / 1000 } }
        let power = BGSoCPower(sampledAt: sampledAt, cpuWatts: watts("cpu_power"),
                               gpuWatts: watts("gpu_power"), aneWatts: watts("ane_power"))
        return power.socWatts == nil ? nil : power
    }
}
