import Foundation
import IOKit

/// Angaben des angeschlossenen Netzteils aus `AppleSmartBattery/AdapterDetails`.
/// Nennwerte beschreiben das ausgehandelte Profil, nicht den tatsächlichen Verbrauch.
struct BGAdapterInfo: Equatable, Sendable {
    var name: String?
    var manufacturer: String?
    var ratedWatts: Double?
    var voltage: Double?
    var current: Double?
    var serialNumber: String?
    var firmwareVersion: String?
    var isWireless: Bool?
}

/// Ein Prozess aus der Energiespalte von `top`. Der Wert ist Apples relative Energiewirkung, keine Wattangabe.
struct BGEnergyConsumer: Equatable, Sendable, Identifiable {
    let pid: Int
    let name: String
    let impact: Double
    var id: Int { pid }
}

enum PowerDetailsReader {
    // MARK: - Netzteil

    /// Read-only snapshot; nil when no adapter is reported.
    static func readAdapter() -> BGAdapterInfo? {
        let service = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return parseAdapter(properties: properties)
    }

    static func parseAdapter(properties: [String: Any]) -> BGAdapterInfo? {
        guard (properties["ExternalConnected"] as? Bool) == true,
              let details = properties["AdapterDetails"] as? [String: Any] else { return nil }
        let info = BGAdapterInfo(
            name: text(details["Name"]),
            manufacturer: text(details["Manufacturer"]),
            ratedWatts: number(details["Watts"], in: 1...1000),
            voltage: number(details["AdapterVoltage"], in: 1...60_000).map { $0 / 1000 },
            current: number(details["Current"], in: 1...20_000).map { $0 / 1000 },
            serialNumber: text(details["SerialString"]),
            firmwareVersion: text(details["FwVersion"]),
            isWireless: details["IsWireless"] as? Bool
        )
        return info == BGAdapterInfo() ? nil : info
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }

    private static func number(_ value: Any?, in range: ClosedRange<Double>) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite && range.contains(double) ? double : nil
    }

    // MARK: - Energiewirkung

    /// Samples `top` twice one second apart; only the second sample contains rates. Blocks about 1–2 s.
    static func readEnergyConsumers(limit: Int = 8) -> [BGEnergyConsumer] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "2", "-s", "1", "-n", String(limit), "-o", "power", "-stats", "pid,power,command"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return parseEnergyConsumers(String(decoding: data, as: UTF8.self), limit: limit)
        } catch { return [] }
    }

    /// Parses the last `PID POWER COMMAND` table; skips idle entries and `top` itself.
    static func parseEnergyConsumers(_ output: String, limit: Int = 8) -> [BGEnergyConsumer] {
        let lines = output.components(separatedBy: .newlines)
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") && $0.contains("POWER") }) else { return [] }
        var consumers: [BGEnergyConsumer] = []
        for line in lines[(header + 1)...] {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int(fields[0]), let impact = Double(fields[1]), impact.isFinite else { continue }
            let name = fields[2].trimmingCharacters(in: .whitespaces)
            guard impact >= 0.1, !name.isEmpty, name != "top" else { continue }
            consumers.append(BGEnergyConsumer(pid: pid, name: name, impact: impact))
        }
        return Array(consumers.sorted { $0.impact > $1.impact }.prefix(limit))
    }
}
