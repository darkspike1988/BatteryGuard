import Foundation
import IOKit
import IOKit.ps

public struct BatteryInfo: Sendable, Equatable {
    public var percent: Int = 0
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
    public static func read(smcClient: SMCClient = .shared) -> BatteryInfo {
        var info = BatteryInfo()

        // 1. Aus IOKit-Registry 'AppleSmartBattery' lesen
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {

                let curCap = (dict["CurrentCapacity"] as? NSNumber)?.intValue ?? 0
                let maxCap = (dict["MaxCapacity"] as? NSNumber)?.intValue ?? 100
                if maxCap > 0 {
                    info.percent = Swift.min(100, Swift.max(0, Int(round(Double(curCap) / Double(maxCap) * 100.0))))
                } else {
                    info.percent = Swift.min(100, Swift.max(0, curCap))
                }

                if let ext = dict["ExternalConnected"] as? NSNumber {
                    info.pluggedIn = ext.boolValue
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

                if let rm = rawMax, let ds = design, ds > 0 {
                    info.healthPercent = Swift.min(100, Swift.max(0, Int(round(Double(rm) / Double(ds) * 100.0))))
                    info.maxCapacityMah = rm
                    info.designCapacityMah = ds
                }
                
                if let timeEmpty = dict["AvgTimeToEmpty"] as? NSNumber, timeEmpty.intValue > 0, timeEmpty.intValue < 65535 {
                    info.timeRemainingMinutes = timeEmpty.intValue
                } else if let timeFull = dict["AvgTimeToFull"] as? NSNumber, timeFull.intValue > 0, timeFull.intValue < 65535 {
                    info.timeRemainingMinutes = timeFull.intValue
                } else if let trc = dict["TimeRemaining"] as? NSNumber, trc.intValue > 0, trc.intValue < 65535 {
                    info.timeRemainingMinutes = trc.intValue
                }

                // Leistung in Watt: Voltage (mV) * Amperage (mA, vorzeichenbehaftet) / 1_000_000
                let rawVolts = (dict["AppleRawBatteryVoltage"] as? NSNumber)?.doubleValue ?? (dict["Voltage"] as? NSNumber)?.doubleValue
                let rawAmpsNum = (dict["Amperage"] as? NSNumber) ?? (dict["InstantAmperage"] as? NSNumber)
                
                if let v = rawVolts, let aNum = rawAmpsNum {
                    var a = aNum.int64Value
                    // UInt64 wrap-around für negative Werte (Entladen) korrigieren, falls NSNumber es als positiv liest
                    if a > 4000000000 {
                        a = Int64(bitPattern: aNum.uint64Value)
                    }
                    info.voltage = v
                    info.amperage = Double(a)
                    info.watts = round((v * Double(a) / 1_000_000.0) * 100.0) / 100.0
                }
            }
            IOObjectRelease(service)
        }

        // 2. Fallback / Abgleich über IOPSCopyPowerSourcesInfo
        if let psBlob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let psList = IOPSCopyPowerSourcesList(psBlob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in psList {
                if let desc = IOPSGetPowerSourceDescription(psBlob, ps)?.takeUnretainedValue() as? [String: Any] {
                    if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                       let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                        info.percent = Swift.min(100, Swift.max(0, Int(round(Double(cur) / Double(maxCap) * 100.0))))
                    }
                    if let state = desc[kIOPSPowerSourceStateKey] as? String {
                        info.pluggedIn = (state != kIOPSBatteryPowerValue)
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

        return info
    }
}
