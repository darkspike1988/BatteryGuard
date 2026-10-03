import SwiftUI
import BatteryGuardShared

struct StatusTilesGridView: View {
    let status: BGStatus
    
    init(status: BGStatus) {
        self.status = status
    }
    
    public var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatusGlassTile(
                icon: "thermometer.medium",
                iconColor: .orange,
                title: "Temperatur",
                value: status.temperatureCelsius != nil ? String(format: "%.1f °C", status.temperatureCelsius!) : "–",
                helpText: "Aktuelle Temperatur des Akkus. (Hitze über 35°C lässt den Akku schneller altern)"
            )
            StatusGlassTile(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .purple,
                title: "Zyklen",
                value: status.cycleCount != nil ? "\(status.cycleCount!)" : "–",
                helpText: "Anzahl der vollständigen Lade-/Entladezyklen. (Apple garantiert 1000 Zyklen)"
            )
            StatusGlassTile(
                icon: "heart.fill",
                iconColor: .red,
                title: "Gesundheit",
                value: status.healthPercent != nil ? "\(status.healthPercent!) %" : "–",
                helpText: "Maximale Kapazität im Vergleich zum Neuzustand."
            )
            StatusGlassTile(
                icon: "bolt.fill",
                iconColor: .yellow,
                title: "Leistung",
                value: status.watts != nil ? String(format: "%.1f W", status.watts!) : "–",
                helpText: "Aktuelle Lade-/Entladeleistung in Watt. (Positiv = Laden, Negativ = Entladen)"
            )
            StatusGlassTile(
                icon: "bolt.horizontal.fill",
                iconColor: .mint,
                title: "Spannung",
                value: status.voltage != nil ? String(format: "%.2f V", status.voltage! / 1000.0) : "–",
                helpText: "Aktuelle Batteriespannung in Volt."
            )
            StatusGlassTile(
                icon: "arrow.up.and.down.and.sparkles",
                iconColor: .cyan,
                title: "Strom",
                value: status.amperage != nil ? String(format: "%.0f mA", status.amperage!) : "–",
                helpText: "Aktueller Stromfluss in Milliampere (mA)."
            )
        }
    }
}

private struct StatusGlassTile: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let helpText: String
    
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 12)
        .help(helpText)
    }
}
