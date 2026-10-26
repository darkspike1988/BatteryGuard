import SwiftUI
import BatteryGuardShared

/// Kennzahlen der Lebensdauer-Analyse; in der App und im PDF-Bericht gleich dargestellt.
struct LifetimeFactsGrid: View {
    let analysis: BGLifetimeAnalysis

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
            row("Beobachtete Zeit", L("%lld h", analysis.observedMinutes / 60))
            row("Temperatur min · Ø · max", [analysis.temperatureMinimum, analysis.temperatureMean, analysis.temperatureMaximum]
                .map { $0.map { String(format: "%.1f °C", $0) } ?? "—" }.joined(separator: " · "))
            row("Zeit unter 20 % · 20–80 % · über 80 %", [analysis.bands.low, analysis.bands.middle, analysis.bands.high]
                .map { String(format: "%.0f %%", $0 * 100) }.joined(separator: " · "))
            row("Ø Laden · Ø Entladen", [analysis.averageChargeWatts, analysis.averageDischargeWatts]
                .map { $0.map { String(format: "%.1f W", $0) } ?? "—" }.joined(separator: " · "))
            row("Kapazitätsquote erster · letzter Tag", [analysis.capacityFirst, analysis.capacityLast]
                .map { $0.map { String(format: "%.1f %%", $0) } ?? "—" }.joined(separator: " · "))
            row("Kapazität je Monat", analysis.capacityChangePerMonth.map { String(format: "%+.2f Prozentpunkte", $0) } ?? L("ab 30 Tagen"))
            row("Zyklen je Monat", analysis.cyclesPerMonth.map { String(format: "%.1f", $0) } ?? L("ab 30 Tagen"))
            row("Tage mit Kapazitätswerten", "\(analysis.trackedDays)")
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
