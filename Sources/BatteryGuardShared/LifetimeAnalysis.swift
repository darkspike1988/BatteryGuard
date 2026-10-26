import Foundation

/// Langzeitauswertung aus dem Minutenverlauf und den Kapazitäts-Tageswerten. Nur gemessene Werte;
/// Lücken werden nicht aufgefüllt, Trends brauchen mindestens 30 Tage Abstand.
public struct BGLifetimeAnalysis: Equatable, Sendable {
    public struct ChargeBands: Equatable, Sendable {
        public var low = 0.0, middle = 0.0, high = 0.0 // Anteile < 20 %, 20–80 %, > 80 %
    }

    public var observedMinutes: Int
    public var temperatureMinimum: Double?
    public var temperatureMaximum: Double?
    public var temperatureMean: Double?
    public var bands: ChargeBands
    public var averageChargeWatts: Double?
    public var averageDischargeWatts: Double?
    public var capacityFirst: Double?
    public var capacityLast: Double?
    public var capacityChangePerMonth: Double?
    public var cyclesFirst: Double?
    public var cyclesLast: Double?
    public var cyclesPerMonth: Double?
    public var trackedDays: Int

    public static func analyze(samples: [BGHistorySample], capacityDays: [BGCapacityDay]) -> BGLifetimeAnalysis {
        let temperatures = samples.compactMap(\.temperature).filter(\.isFinite)
        var bands = ChargeBands()
        if !samples.isEmpty {
            let count = Double(samples.count)
            bands.low = Double(samples.filter { $0.percent < 20 }.count) / count
            bands.high = Double(samples.filter { $0.percent > 80 }.count) / count
            bands.middle = 1 - bands.low - bands.high
        }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let watts = samples.compactMap(\.watts).filter(\.isFinite)
        let days = capacityDays.sorted { $0.day < $1.day }
        let first = days.first, last = days.last
        let spanDays = (first?.day).flatMap { start in (last?.day).map { $0.timeIntervalSince(start) / 86_400 } } ?? 0
        let months = spanDays / 30.44
        let capacityFirst = first.map { $0.mean * 100 }, capacityLast = last.map { $0.mean * 100 }
        let cyclesFirst = days.lazy.compactMap(\.cycleMean).first, cyclesLast = days.reversed().lazy.compactMap(\.cycleMean).first
        return BGLifetimeAnalysis(
            observedMinutes: samples.count,
            temperatureMinimum: temperatures.min(), temperatureMaximum: temperatures.max(), temperatureMean: mean(temperatures),
            bands: bands,
            averageChargeWatts: mean(watts.filter { $0 > 0.1 }),
            averageDischargeWatts: mean(watts.filter { $0 < -0.1 }).map { -$0 },
            capacityFirst: capacityFirst, capacityLast: capacityLast,
            capacityChangePerMonth: spanDays >= 30 ? capacityLast.flatMap { l in capacityFirst.map { (l - $0) / months } } : nil,
            cyclesFirst: cyclesFirst, cyclesLast: cyclesLast,
            cyclesPerMonth: spanDays >= 30 ? cyclesLast.flatMap { l in cyclesFirst.map { (l - $0) / months } } : nil,
            trackedDays: days.count)
    }
}
