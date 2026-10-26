import Foundation
import IOKit
import BatteryGuardShared

/// Firmware, Apples Kalibrierungszustand und gespeicherte Fähigkeiten, alles rein lesend.
enum PlatformInfo {
    static let capabilitiesPath = BGPaths.directory + "/capabilities.json"

    /// System-Firmware aus `IODeviceTree:/chosen` (z. B. „mBoot-20457.1.29“ → „20457.1.29“).
    static func firmwareVersion() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "system-firmware-version" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        return parseFirmware(data)
    }

    static func parseFirmware(_ data: Data) -> String? {
        let text = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.split(separator: "-", maxSplits: 1).last.map(String.init) ?? text
    }

    static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Fragt `PowerUIBatteryMitigationManager` ab: true, solange macOS das Limit für die Kalibrierung aussetzt.
    static func appleCalibrationActive() -> Bool? {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUIBatteryMitigationManager") as? NSObject.Type else { return nil }
        let shared = NSSelectorFromString("sharedManager"), fetch = NSSelectorFromString("fetchCurrentMitigationState")
        guard let sharedMethod = class_getClassMethod(cls, shared) else { return nil }
        typealias SharedFn = @convention(c) (AnyClass, Selector) -> AnyObject?
        typealias FetchFn = @convention(c) (AnyObject, Selector) -> Bool
        guard let manager = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedFn.self)(cls, shared),
              let managerClass = object_getClass(manager),
              let fetchMethod = class_getInstanceMethod(managerClass, fetch) else { return nil }
        return unsafeBitCast(method_getImplementation(fetchMethod), to: FetchFn.self)(manager, fetch)
    }

    /// Vergleicht mit dem gespeicherten Stand und speichert den neuen; liefert die Änderung, falls vorhanden.
    static func recordCapabilities(_ current: BGCapabilities, path: String = capabilitiesPath,
                                   now: Date = Date()) -> BGCapabilityChange? {
        let url = URL(fileURLWithPath: path)
        let previous = (try? Data(contentsOf: url)).flatMap { try? BGJSON.decoder().decode(BGCapabilities.self, from: $0) }
        guard previous != current else { return nil }
        if let data = try? BGJSON.encoder().encode(current) { try? data.write(to: url, options: .atomic) }
        guard let previous else { return nil } // Erster Start: nur merken.
        let changes = current.changes(since: previous)
        return changes.isEmpty ? nil : BGCapabilityChange(detectedAt: now, changes: changes)
    }
}
