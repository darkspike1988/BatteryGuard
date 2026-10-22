import Foundation

/// Modellhafte Alterungsbelastung aus dem lokalen Verlauf. Sie zeigt, wie lange der Akku
/// in welchem Ladebereich war, gewichtet mit einem Temperaturfaktor. Das ist keine
/// Lebensdauerprognose und keine Hardwarediagnose.
///
/// Grundlagen (siehe docs/EVIDENCE.md):
/// - Lagerungsalterung steigt bei Graphitanoden stufenartig mit dem Ladestand; eine
///   deutliche Stufe liegt bei etwa 55–60 % (Keil et al. 2016), hohe Ladestände über
///   80 % altern deutlich stärker (Werner et al. 2021).
/// - Die Temperaturabhängigkeit folgt einem Arrhenius-Gesetz; der Term exp(−6976 K / T)
///   aus Schmalstieg et al. 2014 entspricht etwa 58 kJ/mol: rund 2× bei 35 °C und 4× bei
///   45 °C gegenüber 25 °C.
public struct BGAgingExposure: Equatable, Sendable {
    public enum Band: String, CaseIterable, Sendable {
        /// Unter der Graphitstufe.
        case low
        /// Auf oder knapp über der Stufe.
        case middle
        /// Hoher Ladestand.
        case high
        /// Nahezu voll.
        case full

        public static func of(percent: Int) -> Band {
            switch percent {
            case ..<55: .low
            case ..<80: .middle
            case ..<95: .high
            default: .full
            }
        }

        public var range: ClosedRange<Int> {
            switch self {
            case .low: 0...54
            case .middle: 55...79
            case .high: 80...94
            case .full: 95...100
            }
        }
    }

    /// Bezugstemperatur des Temperaturfaktors.
    public static let referenceCelsius = 25.0
    /// Aktivierungsterm Ea/R in Kelvin (Schmalstieg et al. 2014).
    public static let activationKelvin = 6976.0

    /// Lückenlos beobachtete Zeit in Sekunden.
    public var observedSeconds: TimeInterval = 0
    /// Beobachtete Zeit je Ladebereich.
    public var seconds: [Band: TimeInterval] = [:]
    /// Zeit je Ladebereich, multipliziert mit dem Temperaturfaktor (25 °C = 1).
    public var weightedSeconds: [Band: TimeInterval] = [:]
    /// Zeit ohne Temperaturwert; sie zählt ungewichtet (Faktor 1).
    public var secondsWithoutTemperature: TimeInterval = 0

    public init() {}

    /// Relativer Alterungsfaktor gegenüber 25 °C.
    public static func temperatureFactor(celsius: Double) -> Double {
        let bounded = min(max(celsius, -20), 60)
        let kelvin = bounded + 273.15
        return exp(activationKelvin * (1 / (referenceCelsius + 273.15) - 1 / kelvin))
    }

    /// Mittlerer Temperaturfaktor über die beobachtete Zeit.
    public var averageTemperatureFactor: Double? {
        guard observedSeconds > 0 else { return nil }
        return weightedSeconds.values.reduce(0, +) / observedSeconds
    }

    /// Anteil der beobachteten Zeit ab 80 % Ladung.
    public var highChargeShare: Double? {
        guard observedSeconds > 0 else { return nil }
        return ((seconds[.high] ?? 0) + (seconds[.full] ?? 0)) / observedSeconds
    }

    /// Lücken über zwei Minuten (Schlaf, App beendet) werden wie im Verlauf nicht überbrückt.
    public static func evaluate(_ samples: [BGHistorySample]) -> BGAgingExposure {
        var result = BGAgingExposure()
        for (a, b) in zip(samples, samples.dropFirst()) {
            let duration = b.timestamp.timeIntervalSince(a.timestamp)
            guard duration > 0, duration <= 120 else { continue }
            let band = Band.of(percent: a.percent)
            let factor: Double
            if let temperature = a.temperature, temperature.isFinite {
                factor = temperatureFactor(celsius: temperature)
            } else {
                factor = 1
                result.secondsWithoutTemperature += duration
            }
            result.observedSeconds += duration
            result.seconds[band, default: 0] += duration
            result.weightedSeconds[band, default: 0] += duration * factor
        }
        return result
    }
}
