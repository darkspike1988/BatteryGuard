import Foundation

/// Additive diagnostic contract. Legacy status/API-v1 fields keep their existing units.
public enum BGMetric: String, Codable, CaseIterable, Sendable {
    case chargePercent, batteryTemperature, cycleCount, fullChargeCapacity, designCapacity
    case capacityRatio, batteryPower, batteryVoltage, batteryCurrent, cpuLoad, memoryUsed, memoryTotal
    case swapUsed, volumeAvailable, volumeTotal

    public var unit: String {
        switch self {
        case .chargePercent, .capacityRatio, .cpuLoad: "%"
        case .batteryTemperature: "°C"
        case .cycleCount: "count"
        case .fullChargeCapacity, .designCapacity: "mAh"
        case .batteryPower: "W"
        case .batteryVoltage: "V"
        case .batteryCurrent: "A"
        case .memoryUsed, .memoryTotal, .swapUsed, .volumeAvailable, .volumeTotal: "bytes"
        }
    }

    public func accepts(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch self {
        case .chargePercent, .cpuLoad: return (0...100).contains(value)
        case .batteryTemperature: return (-20...100).contains(value)
        case .cycleCount: return (0...100_000).contains(value) && value == value.rounded()
        case .fullChargeCapacity, .designCapacity: return (1...100_000).contains(value)
        case .capacityRatio: return value > 0
        case .batteryVoltage: return (0.001...50).contains(value)
        case .batteryCurrent: return (-30...30).contains(value)
        case .batteryPower: return (-1500...1500).contains(value)
        case .memoryUsed, .memoryTotal, .swapUsed, .volumeAvailable, .volumeTotal:
            return value >= 0 && value < Double(Int64.max)
        }
    }
}

public enum BGMeasurementSource: String, Codable, Sendable {
    case powerSources = "IOPowerSources"
    case registryCharge = "AppleSmartBattery/CurrentCapacity+MaxCapacity"
    case registryTemperature = "AppleSmartBattery/Temperature"
    case registryCycles = "AppleSmartBattery/CycleCount"
    case rawMaxCapacity = "AppleSmartBattery/AppleRawMaxCapacity"
    case fullChargeCapacity = "AppleSmartBattery/BatteryData/FullChargeCapacity"
    case nominalCapacity = "AppleSmartBattery/BatteryData/NominalChargeCapacity"
    case designCapacity = "AppleSmartBattery/DesignCapacity"
    case nestedDesignCapacity = "AppleSmartBattery/BatteryData/DesignCapacity"
    case registryPower = "AppleSmartBattery/Voltage+Amperage"
    case smcTemperature = "SMC/battery-temperature"
    case capacityCalculation = "full-charge/design-capacity"
    case legacyStatus = "legacy-status/source-unknown"
    case machCPU = "host_statistics/CPU-ticks"
    case machMemory = "host_statistics64/VM"
    case swapUsage = "sysctl/vm.swapusage"
    case volumeCapacity = "URLResourceValues/volume-capacity"
}

public enum BGMeasurementQuality: String, Codable, Sendable {
    case reported, derived, unavailable, unsupported, invalid, stale
}

public enum BGMeasurementReason: String, Codable, Sendable {
    case missing, outOfRange, unverifiedUnit, stale, futureTimestamp, legacySourceUnknown
    case unsupported, insufficientSamples, sourceChanged
}

public struct BGMeasurement: Codable, Equatable, Sendable {
    public let metric: BGMetric
    public let value: Double?
    public var unit: String { metric.unit }
    public let source: BGMeasurementSource
    /// Host read time, never advertised as a firmware refresh time.
    public let sampledAt: Date
    public let sensorUpdatedAt: Date?
    public let quality: BGMeasurementQuality
    public let reason: BGMeasurementReason?

    public init(_ metric: BGMetric, value: Double?, source: BGMeasurementSource, sampledAt: Date,
                sensorUpdatedAt: Date? = nil, quality: BGMeasurementQuality = .reported,
                reason: BGMeasurementReason? = nil) {
        self.metric = metric
        self.source = source
        self.sampledAt = sampledAt
        self.sensorUpdatedAt = sensorUpdatedAt
        if let value, !metric.accepts(value) {
            self.value = nil; self.quality = .invalid; self.reason = .outOfRange
        } else if !sampledAt.timeIntervalSince1970.isFinite ||
                    sensorUpdatedAt.map({ !$0.timeIntervalSince1970.isFinite }) == true {
            self.value = nil; self.quality = .invalid; self.reason = .futureTimestamp
        } else if [.unavailable, .unsupported, .invalid, .stale].contains(quality) {
            self.value = nil; self.quality = quality; self.reason = reason ?? .missing
        } else if let value {
            self.value = value; self.quality = quality; self.reason = reason
        } else {
            self.value = nil; self.quality = .unavailable; self.reason = reason ?? .missing
        }
    }

    public func evaluated(at now: Date, maxAge: TimeInterval = 60) -> BGMeasurement {
        let age = now.timeIntervalSince(sampledAt)
        let sensorAge = sensorUpdatedAt.map { now.timeIntervalSince($0) }
        guard now.timeIntervalSince1970.isFinite, maxAge.isFinite, maxAge >= 0,
              age.isFinite, age >= -5, sensorAge.map({ $0.isFinite && $0 >= -5 }) ?? true else {
            return BGMeasurement(metric, value: nil, source: source, sampledAt: sampledAt,
                                 sensorUpdatedAt: sensorUpdatedAt, quality: .invalid, reason: .futureTimestamp)
        }
        guard age <= maxAge, sensorAge.map({ $0 <= maxAge }) ?? true else {
            return BGMeasurement(metric, value: nil, source: source, sampledAt: sampledAt,
                                 sensorUpdatedAt: sensorUpdatedAt, quality: .stale, reason: .stale)
        }
        return self
    }

    private enum CodingKeys: String, CodingKey { case metric, value, unit, source, sampledAt, sensorUpdatedAt, quality, reason }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let metric = try c.decode(BGMetric.self, forKey: .metric)
        guard try c.decode(String.self, forKey: .unit) == metric.unit else {
            throw DecodingError.dataCorruptedError(forKey: .unit, in: c, debugDescription: "Unexpected unit")
        }
        self.init(metric, value: try c.decodeIfPresent(Double.self, forKey: .value),
                  source: try c.decode(BGMeasurementSource.self, forKey: .source),
                  sampledAt: try c.decode(Date.self, forKey: .sampledAt),
                  sensorUpdatedAt: try c.decodeIfPresent(Date.self, forKey: .sensorUpdatedAt),
                  quality: try c.decode(BGMeasurementQuality.self, forKey: .quality),
                  reason: try c.decodeIfPresent(BGMeasurementReason.self, forKey: .reason))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(metric, forKey: .metric); try c.encodeIfPresent(value, forKey: .value)
        try c.encode(unit, forKey: .unit); try c.encode(source, forKey: .source)
        try c.encode(sampledAt, forKey: .sampledAt); try c.encodeIfPresent(sensorUpdatedAt, forKey: .sensorUpdatedAt)
        try c.encode(quality, forKey: .quality); try c.encodeIfPresent(reason, forKey: .reason)
    }
}

public struct BGBatteryMeasurements: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let values: [BGMeasurement]
    public init(values: [BGMeasurement]) { schemaVersion = 1; self.values = values }

    public func measurement(_ metric: BGMetric, at now: Date = Date()) -> BGMeasurement? {
        values.first { $0.metric == metric }?.evaluated(at: now)
    }

    public static func capacityRatio(maximum: BGMeasurement, design: BGMeasurement) -> BGMeasurement {
        let at = min(maximum.sampledAt, design.sampledAt)
        let sensorAt = [maximum.sensorUpdatedAt, design.sensorUpdatedAt].compactMap { $0 }.min()
        let valid = maximum.metric == .fullChargeCapacity && design.metric == .designCapacity
            && [.reported, .derived].contains(maximum.quality) && [.reported, .derived].contains(design.quality)
        let value = valid && design.value.map({ $0 > 0 }) == true
            ? maximum.value.map { $0 / design.value! * 100 } : nil
        return BGMeasurement(.capacityRatio, value: value, source: .capacityCalculation,
                             sampledAt: at, sensorUpdatedAt: sensorAt, quality: .derived)
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, values }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        let values = try c.decode([BGMeasurement].self, forKey: .values)
        guard version == 1, values.count <= BGMetric.allCases.count,
              Set(values.map(\.metric)).count == values.count else {
            throw DecodingError.dataCorruptedError(forKey: .values, in: c, debugDescription: "Invalid measurement set")
        }
        self.init(values: values)
    }
}

extension BGStatus {
    public func capacityRatioText(at now: Date = Date()) -> String? {
        diagnosticMeasurements(at: now).measurement(.capacityRatio, at: now)?.value.map {
            String(format: "%.1f %%", $0)
        }
    }
    /// Older daemons remain readable, but their source identity is explicitly unknown.
    public func diagnosticMeasurements(at now: Date = Date()) -> BGBatteryMeasurements {
        if let measurements { return BGBatteryMeasurements(values: measurements.values.map { $0.evaluated(at: now) }) }
        func legacy(_ metric: BGMetric, _ value: Double?) -> BGMeasurement {
            BGMeasurement(metric, value: value, source: .legacyStatus, sampledAt: updatedAt,
                          reason: .legacySourceUnknown).evaluated(at: now)
        }
        let maximum = legacy(.fullChargeCapacity, maxCapacityMah.map(Double.init))
        let design = legacy(.designCapacity, designCapacityMah.map(Double.init))
        return BGBatteryMeasurements(values: [
            legacy(.chargePercent, hasBatteryPercent ? Double(percent) : nil),
            legacy(.batteryTemperature, temperatureCelsius), legacy(.cycleCount, cycleCount.map(Double.init)),
            maximum, design, BGBatteryMeasurements.capacityRatio(maximum: maximum, design: design).evaluated(at: now),
            legacy(.batteryPower, watts), legacy(.batteryVoltage, voltage.map { $0 / 1000 }),
            legacy(.batteryCurrent, amperage.map { $0 / 1000 })
        ])
    }
}
