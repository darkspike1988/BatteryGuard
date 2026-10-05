import SwiftUI
import BatteryGuardShared

struct StatusTilesGridView: View {
    let status: BGStatus
    private var measurements: BGBatteryMeasurements { status.diagnosticMeasurements() }
    private func value(_ metric: BGMetric) -> Double? { measurements.measurement(metric)?.value }
    
    init(status: BGStatus) {
        self.status = status
    }
    
    public var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            let temp = value(.batteryTemperature)
            
            StatusGlassTile(
                icon: "thermometer.medium",
                iconColor: .secondary,
                title: "Temperatur",
                value: temp.map { String(format: "%.1f °C", $0) } ?? "–",
                helpText: "Gemeldete Akkutemperatur. Fehlende oder veraltete Werte bleiben unbekannt; keine Aussage über die gesamte Systemthermik."
            )
            StatusGlassTile(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .purple,
                title: "Zyklen",
                value: value(.cycleCount).map { String(format: "%.0f", $0) } ?? "–",
                helpText: "Anzahl der vollständigen Lade-/Entladezyklen. Die Zahl steigt mit der kumulierten Entladung um eine volle Akkukapazität."
            )
            StatusGlassTile(
                icon: "heart.fill",
                iconColor: .red,
                title: "Kapazitätsquote",
                value: status.capacityRatioText() ?? "–",
                helpText: "Berechnetes Verhältnis gemeldeter Maximal- und Designkapazität. Kein allgemeiner Gesundheitswert; kann über 100 % liegen."
            )
            StatusGlassTile(
                icon: "bolt.fill",
                iconColor: .yellow,
                title: "Akku-Leistung",
                value: value(.batteryPower).map { String(format: "%.1f W", $0) } ?? "–",
                helpText: "Stromfluss des Akkus, nicht der gesamte Verbrauch des Mac. Positiv = Laden, negativ = Entladen. Bei 0 W kann das Netzteil den Mac versorgen, ohne den Akku zu laden.",
                detail: batteryPowerDetail
            )
            StatusGlassTile(
                icon: "bolt.horizontal.fill",
                iconColor: .mint,
                title: "Spannung",
                value: value(.batteryVoltage).map { String(format: "%.2f V", $0) } ?? "–",
                helpText: "Aktuelle Batteriespannung in Volt."
            )
            StatusGlassTile(
                icon: "arrow.up.and.down.and.sparkles",
                iconColor: .cyan,
                title: "Strom",
                value: value(.batteryCurrent).map { String(format: "%.2f A", $0) } ?? "–",
                helpText: "Stromfluss in Ampere. Positive Werte laden, negative entladen."
            )
            
            StatusGlassTile(
                icon: "clock.fill",
                iconColor: .blue,
                title: "Restzeit",
                value: timeString,
                helpText: "Verbleibende Zeit bis voll geladen oder leer."
            )
            
            StatusGlassTile(
                icon: "battery.100",
                iconColor: .green,
                title: "Kapazität (mAh)",
                value: capacityString,
                helpText: "Aktuelle maximale Ladung vs. Werks-Designkapazität."
            )
        }
    }
    
    private var batteryPowerDetail: String {
        guard let watts = value(.batteryPower) else { return "Messwert nicht verfügbar" }
        if abs(watts) < 0.05 { return "Kein messbarer Akkustrom" }
        return watts > 0 ? "Fließt in den Akku" : "Fließt aus dem Akku"
    }

    private var timeString: String {
        if value(.chargePercent) != nil, let mins = status.timeRemainingMinutes {
            let h = mins / 60
            let m = mins % 60
            return "\(h)h \(String(format: "%02d", m))m"
        }
        return "–"
    }
    
    private var capacityString: String {
        if let mx = value(.fullChargeCapacity), let ds = value(.designCapacity) {
            return String(format: "%.0f / %.0f", mx, ds)
        }
        return "–"
    }
}

private struct StatusGlassTile: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let helpText: String
    var detail: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 12)
        .help(helpText)
    }
}
