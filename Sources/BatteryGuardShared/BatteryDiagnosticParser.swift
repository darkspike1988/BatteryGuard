import Foundation
import CoreFoundation

/// Pure read-only projection for diagnostics. Does not select or write a control backend.
public enum BGBatteryDiagnosticParser {
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    public static func parse(properties: [String: Any], sampledAt: Date,
                             publicPercent: Int? = nil, fallbackTemperature: Double? = nil) -> BGBatteryMeasurements {
        let nested = properties["BatteryData"] as? [String: Any] ?? [:]
        func value(_ metric: BGMetric, _ number: Double?, _ source: BGMeasurementSource,
                   derived: Bool = false) -> BGMeasurement {
            BGMeasurement(metric, value: number, source: source, sampledAt: sampledAt,
                          quality: derived ? .derived : .reported)
        }
        let maximum: BGMeasurement
        // A present but invalid primary source must not be silently replaced by another source.
        if properties["AppleRawMaxCapacity"] != nil {
            maximum = value(.fullChargeCapacity, number(properties["AppleRawMaxCapacity"]), .rawMaxCapacity)
        } else if nested["FullChargeCapacity"] != nil {
            maximum = value(.fullChargeCapacity, number(nested["FullChargeCapacity"]), .fullChargeCapacity)
        } else {
            maximum = value(.fullChargeCapacity, number(nested["NominalChargeCapacity"]), .nominalCapacity)
        }
        let design = properties["DesignCapacity"] != nil
            ? value(.designCapacity, number(properties["DesignCapacity"]), .designCapacity)
            : value(.designCapacity, number(nested["DesignCapacity"]), .nestedDesignCapacity)
        let percent: BGMeasurement
        if let publicPercent {
            percent = value(.chargePercent, Double(publicPercent), .powerSources)
        } else if let current = number(properties["CurrentCapacity"]), let max = number(properties["MaxCapacity"]),
                  current.isFinite, max.isFinite, max > 0, current >= 0, current <= max {
            percent = value(.chargePercent, current / max * 100, .registryCharge, derived: true)
        } else {
            percent = value(.chargePercent, nil, .registryCharge)
        }
        let temperature = properties["Temperature"] != nil
            ? value(.batteryTemperature, number(properties["Temperature"]).map { $0 / 100 }, .registryTemperature)
            : value(.batteryTemperature, fallbackTemperature, .smcTemperature)
        let voltageRaw = properties["AppleRawBatteryVoltage"] ?? properties["Voltage"]
            ?? nested["AppleRawBatteryVoltage"] ?? nested["Voltage"]
        let voltage = value(.batteryVoltage, number(voltageRaw).map { $0 / 1000 }, .registryPower)
        let rawCurrent = properties["InstantAmperage"] ?? properties["Amperage"]
            ?? nested["InstantAmperage"] ?? nested["Amperage"]
        let current = value(.batteryCurrent, signedCurrent(rawCurrent).map { $0 / 1000 }, .registryPower)
        let watts: Double?
        if let volts = voltage.value, let amps = current.value { watts = volts * amps } else { watts = nil }
        return BGBatteryMeasurements(values: [percent, temperature,
            value(.cycleCount, number(properties["CycleCount"]), .registryCycles), maximum, design,
            BGBatteryMeasurements.capacityRatio(maximum: maximum, design: design), voltage, current,
            value(.batteryPower, watts, .registryPower, derived: true)
        ])
    }

    private static func signedCurrent(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue == n.doubleValue.rounded() else { return nil }
        let type = String(cString: n.objCType)
        if type == "d" || type == "f" { return n.doubleValue }
        let raw = n.uint64Value
        if n.doubleValue < 0 { return n.doubleValue }
        if raw > UInt64(Int64.max) { return Double(Int64(bitPattern: raw)) }
        if raw > UInt64(Int32.max), raw <= UInt64(UInt32.max) { return Double(Int32(bitPattern: UInt32(raw))) }
        return n.doubleValue
    }
}
