import Foundation

public enum BGThermalState: String, Codable, Sendable { case nominal, fair, serious, critical, unknown }

public struct BGSystemSnapshot: Codable, Equatable, Sendable {
    public let modelIdentifier: String?
    public let sampledAt: Date
    public let thermalState: BGThermalState
    public let measurements: BGBatteryMeasurements
    public init(sampledAt: Date, thermalState: BGThermalState, measurements: BGBatteryMeasurements, modelIdentifier: String? = nil) {
        self.sampledAt = sampledAt; self.thermalState = thermalState; self.measurements = measurements
        if let modelIdentifier, modelIdentifier.range(of: "^(MacBookPro|MacBookAir|Mac)[0-9]{1,3},[0-9]{1,3}$", options: .regularExpression) != nil {
            self.modelIdentifier = modelIdentifier
        } else { self.modelIdentifier = nil }
    }
    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(sampledAt)
        return age.isFinite && (-5...60).contains(age)
    }
}

public enum BGBatteryCycleReference {
    /// Deliberately narrow verified mapping; unknown models remain unknown.
    /// Apple support 108052 + 102888, checked 2026-10-05.
    public static func maximumCycles(model: String?) -> Int? {
        guard let model, ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4"].contains(model) else { return nil }
        return 1000
    }
}

public enum BGResourceMath {
    /// Total CPU load, normalized across all processors to 0...100, from monotonically increasing ticks.
    public static func cpuLoad(previous: [UInt64], current: [UInt64]) -> Double? {
        guard previous.count == 4, current.count == 4 else { return nil }
        var deltas: [Double] = []
        for (old, new) in zip(previous, current) {
            guard new >= old else { return nil }
            deltas.append(Double(new - old))
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        // host_cpu_load_info: user, system, idle, nice.
        return (total - deltas[2]) / total * 100
    }
}

public struct BGCapacityDay: Codable, Equatable, Identifiable, Sendable {
    public var id: String { String(day.timeIntervalSince1970) + ":" + maximumSource.rawValue + ":" + designSource.rawValue + ":" + String(designCapacity) + ":" + osVersion }
    public let day: Date
    public let maximumSource: BGMeasurementSource
    public let designSource: BGMeasurementSource
    public let designCapacity: Double
    public let osVersion: String
    public var count: Int
    public var ratioSum: Double
    public var minimum: Double
    public var maximum: Double
    public var firstSampledAt: Date
    public var lastSampledAt: Date
    /// Additive Tageswerte; ältere Dateien bleiben ohne diese Felder gültig.
    public var cycleSum: Double? = nil
    public var cycleSamples: Int = 0
    public var temperatureMaximum: Double? = nil
    public var mean: Double { ratioSum / Double(count) }
    public var cycleMean: Double? {
        guard let cycleSum, cycleSamples > 0 else { return nil }
        return cycleSum / Double(cycleSamples)
    }

    public init(day: Date, maximumSource: BGMeasurementSource, designSource: BGMeasurementSource,
                designCapacity: Double, osVersion: String, count: Int, ratioSum: Double,
                minimum: Double, maximum: Double, firstSampledAt: Date, lastSampledAt: Date,
                cycleSum: Double? = nil, cycleSamples: Int = 0, temperatureMaximum: Double? = nil) {
        self.day = day
        self.maximumSource = maximumSource
        self.designSource = designSource
        self.designCapacity = designCapacity
        self.osVersion = osVersion
        self.count = count
        self.ratioSum = ratioSum
        self.minimum = minimum
        self.maximum = maximum
        self.firstSampledAt = firstSampledAt
        self.lastSampledAt = lastSampledAt
        self.cycleSum = cycleSum
        self.cycleSamples = cycleSamples
        self.temperatureMaximum = temperatureMaximum
    }
    public var isValid: Bool {
        day.timeIntervalSince1970.isFinite && firstSampledAt >= day && lastSampledAt >= firstSampledAt
            && lastSampledAt < day.addingTimeInterval(86400) && (1...1441).contains(count)
            && designCapacity.isFinite && designCapacity > 0 && designCapacity <= 100_000
            && ratioSum.isFinite && ratioSum > 0 && minimum.isFinite && maximum.isFinite
            && minimum > 0 && maximum >= minimum && mean >= minimum - 0.001 && mean <= maximum + 0.001
            && osVersion.count <= 24 && !osVersion.isEmpty
            && osVersion.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            && (cycleSum == nil || (cycleSum!.isFinite && cycleSum! >= 0))
            && (0...1441).contains(cycleSamples)
            && (temperatureMaximum == nil || (temperatureMaximum!.isFinite && (-20...120).contains(temperatureMaximum!)))
    }
}

extension BGCapacityDay {
    private enum CodingKeys: String, CodingKey {
        case day, maximumSource, designSource, designCapacity, osVersion
        case count, ratioSum, minimum, maximum, firstSampledAt, lastSampledAt
        case cycleSum, cycleSamples, temperatureMaximum
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Date.self, forKey: .day)
        maximumSource = try c.decode(BGMeasurementSource.self, forKey: .maximumSource)
        designSource = try c.decode(BGMeasurementSource.self, forKey: .designSource)
        designCapacity = try c.decode(Double.self, forKey: .designCapacity)
        osVersion = try c.decode(String.self, forKey: .osVersion)
        count = try c.decode(Int.self, forKey: .count)
        ratioSum = try c.decode(Double.self, forKey: .ratioSum)
        minimum = try c.decode(Double.self, forKey: .minimum)
        maximum = try c.decode(Double.self, forKey: .maximum)
        firstSampledAt = try c.decode(Date.self, forKey: .firstSampledAt)
        lastSampledAt = try c.decode(Date.self, forKey: .lastSampledAt)
        cycleSum = try c.decodeIfPresent(Double.self, forKey: .cycleSum)
        cycleSamples = try c.decodeIfPresent(Int.self, forKey: .cycleSamples) ?? 0
        temperatureMaximum = try c.decodeIfPresent(Double.self, forKey: .temperatureMaximum)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(day, forKey: .day)
        try c.encode(maximumSource, forKey: .maximumSource)
        try c.encode(designSource, forKey: .designSource)
        try c.encode(designCapacity, forKey: .designCapacity)
        try c.encode(osVersion, forKey: .osVersion)
        try c.encode(count, forKey: .count)
        try c.encode(ratioSum, forKey: .ratioSum)
        try c.encode(minimum, forKey: .minimum)
        try c.encode(maximum, forKey: .maximum)
        try c.encode(firstSampledAt, forKey: .firstSampledAt)
        try c.encode(lastSampledAt, forKey: .lastSampledAt)
        try c.encodeIfPresent(cycleSum, forKey: .cycleSum)
        try c.encode(cycleSamples, forKey: .cycleSamples)
        try c.encodeIfPresent(temperatureMaximum, forKey: .temperatureMaximum)
    }
}

public enum BGCapacityTrend {
    public static let retention: TimeInterval = 365 * 86400
    public static func recording(_ snapshot: BGBatteryMeasurements, in days: [BGCapacityDay],
                                 osVersion: String, at now: Date) -> [BGCapacityDay] {
        let cutoff = now.addingTimeInterval(-retention)
        var next = days.filter { $0.isValid && $0.day >= cutoff && $0.day <= now }.sorted { $0.day < $1.day }
        guard let ratio = snapshot.measurement(.capacityRatio, at: now), let value = ratio.value,
              let max = snapshot.measurement(.fullChargeCapacity, at: now), max.value != nil,
              let design = snapshot.measurement(.designCapacity, at: now), let designValue = design.value else { return next }
        // UTC day buckets are independent of DST and travel timezone changes.
        let day = Date(timeIntervalSince1970: floor(ratio.sampledAt.timeIntervalSince1970 / 86400) * 86400)
        let cycles = snapshot.measurement(.cycleCount, at: now)?.value
        let temperature = snapshot.measurement(.batteryTemperature, at: now)?.value
        var item = BGCapacityDay(day: day, maximumSource: max.source, designSource: design.source,
                                 designCapacity: designValue, osVersion: osVersion,
                                 count: 1, ratioSum: value, minimum: value, maximum: value,
                                 firstSampledAt: ratio.sampledAt, lastSampledAt: ratio.sampledAt)
        item.cycleSamples = cycles == nil ? 0 : 1
        item.cycleSum = cycles
        item.temperatureMaximum = temperature
        guard item.isValid else { return next }
        if let index = next.firstIndex(where: { $0.id == item.id }) {
            let previous = next[index]
            guard ratio.sampledAt.timeIntervalSince(previous.lastSampledAt) >= 60, previous.count < 1441 else { return next }
            item.count = previous.count + 1; item.ratioSum = previous.ratioSum + value
            item.minimum = Swift.min(previous.minimum, value); item.maximum = Swift.max(previous.maximum, value)
            item.firstSampledAt = previous.firstSampledAt
            item.cycleSamples = previous.cycleSamples + item.cycleSamples
            item.cycleSum = [previous.cycleSum, item.cycleSum].compactMap { $0 }.reduce(0, +)
            if let old = previous.temperatureMaximum, let new = item.temperatureMaximum {
                item.temperatureMaximum = Swift.max(old, new)
            } else {
                item.temperatureMaximum = item.temperatureMaximum ?? previous.temperatureMaximum
            }
            next[index] = item
        } else { next.append(item) }
        return Array(next.sorted { $0.lastSampledAt < $1.lastSampledAt }.suffix(1464))
    }

    public static func csv(_ days: [BGCapacityDay]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var rows = ["day_utc,capacity_percent,minimum_percent,maximum_percent,samples,cycle_mean,temperature_max_c,maximum_source,design_source,design_capacity_mah,os_version"]
        rows += days.filter(\.isValid).sorted { $0.day < $1.day }.map { day in
            [formatter.string(from: day.day),
             decimal(day.mean), decimal(day.minimum), decimal(day.maximum), String(day.count),
             day.cycleMean.map(decimal) ?? "",
             day.temperatureMaximum.map(decimal) ?? "",
             day.maximumSource.rawValue, day.designSource.rawValue,
             decimal(day.designCapacity), day.osVersion].joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// A descriptive delta, not an aging forecast. Mixed sources/design/OS never produce a delta.
    public static func change(_ days: [BGCapacityDay]) -> Double? {
        let sorted = days.filter(\.isValid).sorted { $0.day < $1.day }
        guard let first = sorted.first, let last = sorted.last, sorted.count >= 3,
              last.day.timeIntervalSince(first.day) >= 2 * 86400,
              sorted.allSatisfy({ $0.maximumSource == first.maximumSource && $0.designSource == first.designSource
                  && $0.designCapacity == first.designCapacity && $0.osVersion == first.osVersion }) else { return nil }
        return last.mean - first.mean
    }
}

public enum BGDiagnosticIssue: String, Codable, Sendable, CaseIterable {
    case batteryDataUnavailable, capacityIsEstimate, legacySourceUnknown, systemDataUnavailable
    case thermalElevated, thermalCritical, cpuBusy, volumeCapacityUnavailable
}

public enum BGDiagnosticRules {
    public static func evaluate(battery: BGBatteryMeasurements, system: BGSystemSnapshot?,
                                at now: Date) -> [BGDiagnosticIssue] {
        var issues: [BGDiagnosticIssue] = []
        if battery.measurement(.chargePercent, at: now)?.value == nil { issues.append(.batteryDataUnavailable) }
        if battery.measurement(.capacityRatio, at: now)?.value != nil { issues.append(.capacityIsEstimate) }
        if battery.values.contains(where: { $0.source == .legacyStatus && $0.evaluated(at: now).value != nil }) {
            issues.append(.legacySourceUnknown)
        }
        guard let system, system.isFresh(at: now) else { issues.append(.systemDataUnavailable); return issues }
        if system.thermalState == .critical { issues.append(.thermalCritical) }
        else if system.thermalState == .serious { issues.append(.thermalElevated) }
        if let cpu = system.measurements.measurement(.cpuLoad, at: now)?.value, cpu >= 90 {
            // Informational instantaneous load; never presented as a fault or persistent overheating.
            issues.append(.cpuBusy)
        }
        if system.measurements.measurement(.volumeAvailable, at: now)?.value == nil { issues.append(.volumeCapacityUnavailable) }
        return issues
    }
}
