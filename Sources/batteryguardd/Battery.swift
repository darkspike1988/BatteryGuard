import Foundation
import IOKit
import IOKit.ps
import BatteryGuardShared

public struct BatteryInfo: Sendable, Equatable {
    public var measurements: BGBatteryMeasurements? = nil
    public var percent: Int = 0
    public var percentAvailable: Bool = true
    public var externalPowerAvailable: Bool = true
    public var pluggedIn: Bool = false
    public var isCharging: Bool = false
    public var temperatureCelsius: Double? = nil
    public var cycleCount: Int? = nil
    public var healthPercent: Int? = nil
    public var watts: Double? = nil
    public var voltage: Double? = nil
    public var amperage: Double? = nil
    public var timeRemainingMinutes: Int? = nil
    public var maxCapacityMah: Int? = nil
    public var designCapacityMah: Int? = nil

    public init() {}
}

public enum BatteryReader {
    /// Registry-Werte können negative Ströme als UInt32 oder UInt64 enthalten.
    public static func signedAmperage(_ raw: UInt64) -> Int64 {
        if raw <= UInt64(UInt32.max), raw > UInt64(Int32.max) {
            return Int64(Int32(bitPattern: UInt32(raw)))
        }
        return Int64(bitPattern: raw)
    }

    public static func batteryPower(voltageMillivolts: Double?, amperageRaw: UInt64?) -> Double? {
        guard let voltageMillivolts, voltageMillivolts.isFinite, voltageMillivolts > 0,
              let amperageRaw else { return nil }
        let watts = voltageMillivolts * Double(signedAmperage(amperageRaw)) / 1_000_000
        return watts.isFinite ? round(watts * 100) / 100 : nil
    }

    public static func read(smcClient: SMCClient = .shared) -> BatteryInfo {
        var info = BatteryInfo()
        var diagnosticProperties: [String: Any] = [:]
        var publicPercent: Int?
        info.percentAvailable = false
        info.externalPowerAvailable = false

        // 1. Aus IOKit-Registry 'AppleSmartBattery' lesen
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                diagnosticProperties = dict

                if let curCap = (dict["CurrentCapacity"] as? NSNumber)?.intValue,
                   let maxCap = (dict["MaxCapacity"] as? NSNumber)?.intValue,
                   curCap >= 0, maxCap > 0, curCap <= maxCap {
                    info.percent = Int(round(Double(curCap) / Double(maxCap) * 100))
                    info.percentAvailable = true
                }

                if let ext = dict["ExternalConnected"] as? NSNumber {
                    info.pluggedIn = ext.boolValue
                    info.externalPowerAvailable = true
                }

                if let chg = dict["IsCharging"] as? NSNumber {
                    info.isCharging = chg.boolValue
                }

                if let temp = dict["Temperature"] as? NSNumber {
                    info.temperatureCelsius = round(temp.doubleValue / 100.0 * 10.0) / 10.0
                }

                if let cycles = dict["CycleCount"] as? NSNumber {
                    info.cycleCount = cycles.intValue
                }

                // Health-Berechnung: AppleRawMaxCapacity / DesignCapacity
                let bData = dict["BatteryData"] as? [String: Any]
                let rawMax = (dict["AppleRawMaxCapacity"] as? NSNumber)?.intValue
                    ?? (bData?["FullChargeCapacity"] as? NSNumber)?.intValue
                    ?? (bData?["NominalChargeCapacity"] as? NSNumber)?.intValue
                let design = (dict["DesignCapacity"] as? NSNumber)?.intValue
                    ?? (bData?["DesignCapacity"] as? NSNumber)?.intValue

                if let rm = rawMax, let ds = design, (1...100_000).contains(rm), (1...100_000).contains(ds) {
                    info.healthPercent = Swift.min(100, Swift.max(0, Int(round(Double(rm) / Double(ds) * 100.0))))
                    info.maxCapacityMah = rm
                    info.designCapacityMah = ds
                }
                
                let timeKey = info.isCharging ? "AvgTimeToFull" : "AvgTimeToEmpty"
                if let time = dict[timeKey] as? NSNumber, time.intValue > 0, time.intValue < 65535 {
                    info.timeRemainingMinutes = time.intValue
                } else if let time = dict["TimeRemaining"] as? NSNumber, time.intValue > 0, time.intValue < 65535 {
                    info.timeRemainingMinutes = time.intValue
                }

                // Leistung in Watt: Voltage (mV) * Amperage (mA, vorzeichenbehaftet) / 1_000_000
                let rawVolts = (dict["AppleRawBatteryVoltage"] as? NSNumber)?.doubleValue ?? (dict["Voltage"] as? NSNumber)?.doubleValue
                    ?? (bData?["AppleRawBatteryVoltage"] as? NSNumber)?.doubleValue
                    ?? (bData?["Voltage"] as? NSNumber)?.doubleValue
                let rawAmpsNum = (dict["InstantAmperage"] as? NSNumber) ?? (dict["Amperage"] as? NSNumber)
                    ?? (bData?["InstantAmperage"] as? NSNumber) ?? (bData?["Amperage"] as? NSNumber)
                
                if let v = rawVolts, let aNum = rawAmpsNum {
                    let a = signedAmperage(aNum.uint64Value)
                    info.voltage = v
                    info.amperage = Double(a)
                    info.watts = batteryPower(voltageMillivolts: v, amperageRaw: aNum.uint64Value)
                }
            }
            IOObjectRelease(service)
        }

        // 2. Fallback / Abgleich über IOPSCopyPowerSourcesInfo
        if let psBlob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let psList = IOPSCopyPowerSourcesList(psBlob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in psList {
                if let desc = IOPSGetPowerSourceDescription(psBlob, ps)?.takeUnretainedValue() as? [String: Any] {
                    guard desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                    if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                       let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0, cur >= 0, cur <= maxCap {
                        info.percent = Int(round(Double(cur) / Double(maxCap) * 100.0))
                        info.percentAvailable = true
                        publicPercent = info.percent
                    }
                    if let state = desc[kIOPSPowerSourceStateKey] as? String,
                       state == kIOPSBatteryPowerValue || state == kIOPSACPowerValue {
                        info.pluggedIn = (state != kIOPSBatteryPowerValue)
                        info.externalPowerAvailable = true
                    }
                    if let chg = desc[kIOPSIsChargingKey] as? Bool {
                        info.isCharging = chg
                    }
                }
            }
        }

        // 3. Fallback für Temperatur via SMC (z. B. auf Apple Silicon)
        if info.temperatureCelsius == nil {
            info.temperatureCelsius = smcClient.readBatteryTemperature()
        }

        info.measurements = BGBatteryDiagnosticParser.parse(properties: diagnosticProperties, sampledAt: Date(),
            publicPercent: publicPercent, fallbackTemperature: info.temperatureCelsius)

        return info
    }
}
