import Foundation

import CoreGraphics
import IOKit

/// Keep AC power available before closing the lid, not only after it closes.
/// A failed display/registry query also keeps power connected.
enum DesktopEnvironment {
    static func allowsAdapterDisconnect() -> Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success,
              count > 0, count < displays.count else { return false }
        guard !displays.prefix(Int(count)).contains(where: { CGDisplayIsBuiltin($0) == 0 }) else {
            return false
        }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
            return false
        }
        return !value.boolValue
    }
}
