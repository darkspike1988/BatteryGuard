import SwiftUI
import BatteryGuardShared

public struct PowerFlowView: View {
    private let sample: BGPowerFlowSample?
    private let compact: Bool

    public init(sample: BGPowerFlowSample?, compact: Bool = false) {
        self.sample = sample
        self.compact = compact
    }

    private var isFresh: Bool { sample?.isFresh() ?? false }

    public var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                HStack {
                    Label("Energiefluss", systemImage: "bolt.horizontal.fill")
                        .font(compact ? .headline : .title3.weight(.semibold))
                    Spacer()
                    if !isFresh {
                        Text("Nicht aktuell")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                if compact {
                    VStack(spacing: 8) {
                        compactRow(icon: "powerplug.fill", title: "Netzteil", detail: ratedWattsText ?? "Gemeldet", value: formatWatts(sample?.inputWatts))
                        Image(systemName: isFresh && (sample?.inputWatts ?? 0) > 0.5 ? "arrow.down" : "minus")
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary.opacity(0.7))
                        compactRow(icon: "laptopcomputer", title: "Mac", detail: "Abgeleiteter Verbrauch", value: formatWatts(sample?.systemWatts))
                        Image(systemName: batteryArrow(vertical: true))
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary.opacity(0.7))
                        compactRow(icon: batteryIcon, title: "Akku", detail: [batteryStatus, hardwarePercentText].compactMap { $0 }.joined(separator: " • "), value: formatSignedWatts(sample?.batteryWatts))
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        nodeCard(title: "Netzteil", subtitle: "Eingang (gemeldet)", icon: "powerplug.fill", value: formatWatts(sample?.inputWatts), extra: ratedWattsText)
                        flowIndicator(symbol: isFresh && (sample?.inputWatts ?? 0) > 0.5 ? "arrow.right" : "minus", label: "Eingang")
                        nodeCard(title: "Mac", subtitle: "System (abgeleitet)", icon: "laptopcomputer", value: formatWatts(sample?.systemWatts), extra: nil)
                        flowIndicator(symbol: batteryArrow(vertical: false), label: batteryStatus)
                        nodeCard(title: "Akku", subtitle: batteryStatus, icon: batteryIcon, value: formatSignedWatts(sample?.batteryWatts), extra: hardwarePercentText)
                    }
                }
                Text("Mac-Leistung geschätzt aus Eingang minus Akkufluss. Bei Akkubetrieb gilt Eingang 0 W. Nennleistung ist kein Verbrauch.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func nodeCard(title: String, subtitle: String, icon: String, value: String, extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text(value).font(.title2.weight(.medium).monospacedDigit())
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            if let extra {
                Text(extra).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func compactRow(icon: String, title: String, detail: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private func flowIndicator(symbol: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(width: 52)
    }

    private func formatWatts(_ watts: Double?) -> String {
        guard isFresh, let watts else { return "—" }
        return String(format: "%.1f W", max(0, watts))
    }

    private func formatSignedWatts(_ watts: Double?) -> String {
        guard isFresh, let watts else { return "—" }
        if abs(watts) <= 0.1 { return "0.0 W" }
        return String(format: "%@%.1f W", watts > 0 ? "+" : "", watts)
    }

    private var ratedWattsText: String? {
        guard isFresh, let rated = sample?.adapterRatedWatts, rated > 0 else { return nil }
        return "Nennleistung: \(Int(round(rated))) W"
    }

    private var hardwarePercentText: String? {
        guard isFresh, let hw = sample?.hardwarePercent else { return nil }
        return "Hardware: \(Int(round(hw))) % (Schätzwert)"
    }

    private var batteryStatus: String {
        guard isFresh, let w = sample?.batteryWatts else { return "Lade-/Entladefluss" }
        if w > 0.1 { return "Lädt" }
        if w < -0.1 { return "Entlädt" }
        return "Nahe 0 W"
    }

    private var batteryIcon: String {
        guard isFresh, let w = sample?.batteryWatts, w > 0.1 else { return "battery.100" }
        return "battery.100bolt"
    }

    private func batteryArrow(vertical: Bool) -> String {
        guard isFresh, let w = sample?.batteryWatts else { return "minus" }
        if w > 0.1 { return vertical ? "arrow.down" : "arrow.right" }
        if w < -0.1 { return vertical ? "arrow.up" : "arrow.left" }
        return "minus"
    }

    private var accessibilitySummary: String {
        guard isFresh, let sample else { return "Energiefluss: Keine aktuellen Messwerte verfügbar." }
        var parts: [String] = ["Energiefluss:"]
        if let input = sample.inputWatts { parts.append("Netzteileingang \(String(format: "%.1f", input)) Watt.") }
        if let rated = sample.adapterRatedWatts { parts.append("Nennleistung \(Int(round(rated))) Watt.") }
        if let sys = sample.systemWatts { parts.append("Mac-Verbrauch geschätzt \(String(format: "%.1f", sys)) Watt.") }
        if let bat = sample.batteryWatts {
            if bat > 0.1 { parts.append("Akku lädt mit \(String(format: "%.1f", bat)) Watt.") }
            else if bat < -0.1 { parts.append("Akku entlädt mit \(String(format: "%.1f", abs(bat))) Watt.") }
            else { parts.append("Akkufluss nahe null Watt.") }
        }
        if let hw = sample.hardwarePercent { parts.append("Hardware-Ladestand \(Int(round(hw))) Prozent Schätzwert.") }
        if parts.count == 1 { return "Energiefluss: Keine Messwerte verfügbar." }
        return parts.joined(separator: " ")
    }
}
