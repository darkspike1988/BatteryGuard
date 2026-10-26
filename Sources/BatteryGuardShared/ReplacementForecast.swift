import Foundation

/// Grobe Prognose, wann die Kapazitätsquote 80 % oder die Zyklusreferenz erreicht.
/// Grundlage ist eine lineare Regression über Tageswerte gleicher Quelle und Designkapazität.
/// Echte Alterung verläuft nicht linear und schwankt mit Temperatur und Nutzung; die Spanne
/// aus dem Standardfehler der Steigung zeigt, wie unsicher die Schätzung ist.
public struct BGReplacementForecast: Equatable, Sendable {
    public static let capacityThreshold = 80.0
    public static let minimumSpanDays = 30.0
    public static let minimumDays = 10
    /// Weiter als so viele Jahre wird kein Datum genannt.
    public static let horizonYears = 15.0
    /// Apple ersetzt Akkus unter AppleCare+ unter 80 % der ursprünglichen Kapazität.
    public static let appleCareReminderWindow: TimeInterval = 90 * 86400
    public static let appleCareCapacityMargin = 82.0

    public enum Status: Equatable, Sendable {
        case insufficientData(daysCollected: Int, spanDays: Int)
        case noMeasurableDecline
        case declining
    }

    public var status: Status
    public var currentCapacity: Double?
    /// Prozentpunkte pro Jahr (negativ = Abnahme).
    public var changePerYear: Double?
    public var capacityThresholdDate: Date?
    public var capacityThresholdEarliest: Date?
    public var capacityThresholdLatest: Date?
    public var cyclesPerDay: Double?
    public var cycleLimit: Int?
    public var cycleLimitDate: Date?
    /// Ein kürzlich geändertes Ladelimit verschiebt die Messung vorübergehend.
    public var settling: Bool
    public var appleCareReminderDue: Bool

    public static func evaluate(days: [BGCapacityDay], currentCycles: Int?, cycleLimit: Int?,
                                appleCareEnd: Date?, limitChange: BGLimitChange?,
                                now: Date = Date()) -> BGReplacementForecast {
        let valid = days.filter(\.isValid).sorted { $0.day < $1.day }
        let comparable = valid.last.map { last in
            valid.filter { $0.maximumSource == last.maximumSource && $0.designSource == last.designSource
                && $0.designCapacity == last.designCapacity }
        } ?? []
        let settling = limitChange?.isSettling(at: now) ?? false

        var forecast = BGReplacementForecast(status: .noMeasurableDecline, currentCapacity: comparable.last?.mean,
                                             settling: settling, appleCareReminderDue: false)
        forecast.cycleLimit = cycleLimit
        forecast.estimateCycles(days: comparable, currentCycles: currentCycles, limit: cycleLimit, now: now)

        let span = comparable.count >= 2 ? comparable.last!.day.timeIntervalSince(comparable.first!.day) / 86400 : 0
        if comparable.count < minimumDays || span < minimumSpanDays {
            forecast.status = .insufficientData(daysCollected: comparable.count, spanDays: Int(span))
        } else if let fit = regression(comparable) {
            forecast.currentCapacity = fit.value(at: now)
            forecast.changePerYear = fit.slopePerDay * 365
            if fit.slopePerDay < 0 {
                forecast.status = .declining
                let current = fit.value(at: now)
                forecast.capacityThresholdDate = date(from: current, slope: fit.slopePerDay, now: now)
                // Steilere Steigung ergibt das früheste, flachere das späteste Datum.
                forecast.capacityThresholdEarliest = date(from: current, slope: fit.slopePerDay - 2 * fit.slopeError, now: now)
                forecast.capacityThresholdLatest = date(from: current, slope: fit.slopePerDay + 2 * fit.slopeError, now: now)
            }
        }

        if let appleCareEnd, appleCareEnd > now,
           appleCareEnd.timeIntervalSince(now) <= appleCareReminderWindow {
            let lowNow = (forecast.currentCapacity ?? 100) <= appleCareCapacityMargin
            let reachesBeforeEnd = forecast.capacityThresholdEarliest.map { $0 <= appleCareEnd } ?? false
            forecast.appleCareReminderDue = lowNow || reachesBeforeEnd
        }
        return forecast
    }

    private static func date(from current: Double, slope: Double, now: Date) -> Date? {
        guard current > capacityThreshold else { return now }
        guard slope < 0 else { return nil }
        let days = (current - capacityThreshold) / -slope
        guard days.isFinite, days <= horizonYears * 365 else { return nil }
        return now.addingTimeInterval(days * 86400)
    }

    private mutating func estimateCycles(days: [BGCapacityDay], currentCycles: Int?, limit: Int?, now: Date) {
        let points = days.compactMap { day in day.cycleMean.map { (day.day, $0) } }
        guard let first = points.first, let last = points.last else { return }
        let span = last.0.timeIntervalSince(first.0) / 86400
        guard span >= Self.minimumSpanDays else { return }
        let rate = (last.1 - first.1) / span
        guard rate.isFinite, rate >= 0 else { return }
        cyclesPerDay = rate
        guard let limit, rate > 0 else { return }
        let current = Double(currentCycles ?? Int(last.1.rounded()))
        guard current < Double(limit) else { cycleLimitDate = now; return }
        let remaining = (Double(limit) - current) / rate
        guard remaining <= Self.horizonYears * 365 else { return }
        cycleLimitDate = now.addingTimeInterval(remaining * 86400)
    }

    struct Fit {
        var intercept: Double
        var slopePerDay: Double
        var slopeError: Double
        var origin: Date
        func value(at date: Date) -> Double {
            intercept + slopePerDay * date.timeIntervalSince(origin) / 86400
        }
    }

    static func regression(_ days: [BGCapacityDay]) -> Fit? {
        guard days.count >= 3, let origin = days.first?.day else { return nil }
        let xs = days.map { $0.day.timeIntervalSince(origin) / 86400 }
        let ys = days.map(\.mean)
        let n = Double(days.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let residuals = zip(xs, ys).reduce(0) { $0 + pow($1.1 - (intercept + slope * $1.0), 2) }
        let error = sqrt(residuals / (n - 2) / sxx)
        guard slope.isFinite, intercept.isFinite, error.isFinite else { return nil }
        return Fit(intercept: intercept, slopePerDay: slope, slopeError: error, origin: origin)
    }
}
