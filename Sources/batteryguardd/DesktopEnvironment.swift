import Foundation

import CoreGraphics
import IOKit

/// Keep AC power available before closing the lid, not only after it closes.
/// A failed display/registry query also keeps power connected.
public enum DesktopEnvironment {
    public struct Snapshot: Sendable {
        public var externalDisplayConnected: Bool
        public var lidClosed: Bool?
        public var allowsAdapterDisconnect: Bool
    }

    static func snapshot() -> Snapshot {
        var displays = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        let displayQueryOK = CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success
            && count > 0 && count < displays.count
        let external = displayQueryOK
            ? displays.prefix(Int(count)).contains(where: { CGDisplayIsBuiltin($0) == 0 })
            : false

        let lid = clamshellClosed()
        // A failed display or lid query must keep the adapter connected.
        let allows = displayQueryOK && !external && (lid ?? true) == false
        return Snapshot(externalDisplayConnected: external, lidClosed: lid, allowsAdapterDisconnect: allows)
    }

    static func allowsAdapterDisconnect() -> Bool {
        snapshot().allowsAdapterDisconnect
    }

    private static func clamshellClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
            return nil
        }
        return value.boolValue
    }
}
