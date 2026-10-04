import Foundation
import IOKit
import BatteryGuardShared

enum PowerFlowReader {
    static let sourceName = "AppleSmartBattery/PowerTelemetryData"

    private static let inputMilliwattRange: ClosedRange<Double> = 0...1_000_000
    private static let voltageRange: ClosedRange<Double> = 1...50_000
    private static let currentRange: ClosedRange<Int64> = -30_000...30_000
    private static let maxAdapterWatts = 1000.0

    /// Takes a single read-only snapshot of the AppleSmartBattery registry properties.
    static func read() -> BGPowerFlowSample? {
        let service = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let unmanaged else { return nil }
        let cfProperties = unmanaged.takeRetainedValue()
        guard let properties = cfProperties as? [String: Any] else { return nil }

        return parse(properties: properties, sampledAt: Date())
    }

    static func parse(properties: [String: Any], sampledAt: Date = Date()) -> BGPowerFlowSample {
        let plugged = booleanValue(properties["ExternalConnected"])

        var inputWatts: Double?
        var adapterRatedWatts: Double?

        if plugged == true {
            if let telemetry = properties["PowerTelemetryData"] as? [String: Any],
               let milliwatts = finiteNumber(telemetry["SystemPowerIn"]),
               inputMilliwattRange.contains(milliwatts) {
                inputWatts = milliwatts / 1000.0
            }

            if let details = properties["AdapterDetails"] as? [String: Any],
               let watts = finiteNumber(details["Watts"]),
               watts > 0, watts <= maxAdapterWatts {
                adapterRatedWatts = watts
            }
        } else if plugged == false {
            inputWatts = 0
        }

        return BGPowerFlowSample(
            sampledAt: sampledAt,
            inputWatts: inputWatts,
            batteryWatts: batteryWatts(from: properties),
            adapterRatedWatts: adapterRatedWatts,
            hardwarePercent: hardwarePercent(from: properties),
            source: sourceName
        )
    }

    // MARK: - Derived values

    private static func batteryWatts(from properties: [String: Any]) -> Double? {
        guard let millivolts = finiteNumber(properties["Voltage"]),
              voltageRange.contains(millivolts) else { return nil }

        // Fallback to Amperage only when InstantAmperage is absent (not when invalid).
        let rawCurrent: Any?
        if let instant = properties["InstantAmperage"] {
            rawCurrent = instant
        } else {
            rawCurrent = properties["Amperage"]
        }

        guard let milliamps = signedInteger(rawCurrent),
              currentRange.contains(milliamps) else { return nil }

        let watts = millivolts * Double(milliamps) / 1_000_000.0
        return watts.isFinite ? watts : nil
    }

    private static func hardwarePercent(from properties: [String: Any]) -> Double? {
        guard let current = finiteNumber(properties["AppleRawCurrentCapacity"]),
              let maximum = finiteNumber(properties["AppleRawMaxCapacity"]),
              current >= 0, maximum > 0 else { return nil }
        let percent = current / maximum * 100.0
        guard percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent
    }

    // MARK: - Value decoding

    private static func number(_ value: Any?) -> NSNumber? {
        guard let value, let number = value as? NSNumber else { return nil }
        // Reject Boolean values bridged as NSNumber.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number
    }

    private static func booleanValue(_ value: Any?) -> Bool? {
        guard let value, let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        switch CFNumberGetType(number) {
        case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
            return true
        default:
            return false
        }
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = number(value) else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// Decodes an integer-valued NSNumber, interpreting uint32/uint64 two's complement values as signed.
    private static func signedInteger(_ value: Any?) -> Int64? {
        guard let number = number(value) else { return nil }

        if isFloatingPoint(number) {
            let double = number.doubleValue
            guard double.isFinite, double == double.rounded(),
                  double >= Double(Int64.min), double < Double(Int64.max) else { return nil }
            return Int64(double)
        }

        let type = String(cString: number.objCType)
        let unsignedTypes: Set<String> = ["C", "S", "I", "L", "Q"]

        let raw: UInt64
        if unsignedTypes.contains(type) {
            raw = number.uint64Value
        } else {
            let signed = number.int64Value
            if signed < 0 { return signed }
            raw = UInt64(signed)
        }

        if raw > UInt64(Int64.max) {
            return Int64(bitPattern: raw)           // uint64 two's complement
        }
        if raw > UInt64(Int32.max) && raw <= UInt64(UInt32.max) {
            return Int64(Int32(bitPattern: UInt32(raw)))  // uint32 two's complement
        }
        return Int64(raw)
    }
}
