import Foundation
import IOKit

/// Akkustand eines verbundenen Geräts (Maus, Tastatur, AirPods). Nur gemeldete Werte, keine Schätzung.
struct BGDeviceBattery: Equatable, Sendable, Identifiable {
    var name: String
    var kind: String?
    /// Teilwerte, z. B. ["": 80] oder ["Links": 70, "Rechts": 72, "Case": 40].
    var levels: [String: Int]
    var id: String { name }
}

enum DeviceBatteryReader {
    /// Liest `system_profiler SPBluetoothDataType -json` (etwa eine Sekunde) und HID-Geräte aus der IORegistry.
    static func read() -> [BGDeviceBattery] {
        var devices = parseBluetooth(runSystemProfiler() ?? Data())
        for device in readHID() where !devices.contains(where: { $0.name == device.name }) {
            devices.append(device)
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parseBluetooth(_ data: Data) -> [BGDeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controller = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = controller["device_connected"] as? [[String: Any]] else { return [] }
        let parts = [("device_batteryLevelMain", ""), ("device_batteryLevel", ""), ("device_batteryLevelLeft", "Links"),
                     ("device_batteryLevelRight", "Rechts"), ("device_batteryLevelCase", "Case")]
        return connected.flatMap { entry in
            entry.compactMap { name, value -> BGDeviceBattery? in
                guard let properties = value as? [String: Any] else { return nil }
                var levels: [String: Int] = [:]
                for (key, label) in parts {
                    if let level = percent(properties[key]), levels[label] == nil { levels[label] = level }
                }
                guard !levels.isEmpty else { return nil }
                return BGDeviceBattery(name: name, kind: properties["device_minorType"] as? String, levels: levels)
            }
        }
    }

    static func percent(_ value: Any?) -> Int? {
        let text = (value as? String)?.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let number = text.flatMap(Int.init) ?? (value as? Int), (0...100).contains(number) else { return nil }
        return number
    }

    private static func runSystemProfiler() -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch { return nil }
    }

    /// Apple-HID-Geräte (Magic Mouse/Keyboard/Trackpad) melden `BatteryPercent` in der IORegistry.
    private static func readHID() -> [BGDeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [BGDeviceBattery] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(service, key as CFString, nil, 0)?.takeRetainedValue() }
            guard let level = percent(property("BatteryPercent")), let name = property("Product") as? String else { continue }
            result.append(BGDeviceBattery(name: name, kind: nil, levels: ["": level]))
        }
        return result
    }
}
