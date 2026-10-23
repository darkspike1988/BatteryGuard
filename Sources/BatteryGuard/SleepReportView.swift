import SwiftUI
import BatteryGuardShared

/// Letzte Schlafphase auf Akku und was den Mac gerade wach hält.
struct SleepReportView: View {
    private let store = SleepReportStore.shared

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Schlafbericht").font(.headline)
                    Spacer()
                    if store.isLoading { ProgressView().controlSize(.small) }
                    Button("Aktualisieren") {
                        store.refreshBlockers()
                        Task { await store.refresh() }
                    }.font(.caption).disabled(store.isLoading)
                }
                if let report = store.report {
                    sessionView(report)
                } else if store.hasLoaded {
                    Text("Noch keine Schlafphase auf Akku gefunden. Der Bericht erscheint nach dem nächsten Schlaf von mindestens 30 Minuten ohne Netzteil.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("Was hält den Mac gerade wach?").font(.subheadline.weight(.semibold))
                if store.blockers.isEmpty {
                    Text("Nichts – der Mac kann in den Ruhezustand wechseln.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(store.blockers) { blocker in
                        Label {
                            Text(blocker.name.isEmpty ? blocker.process : "\(blocker.process): \(blocker.name)")
                                .font(.callout)
                        } icon: {
                            Image(systemName: "moon.zzz").foregroundStyle(.orange)
                        }
                    }
                }
                Text("Quelle: Energieprotokoll von macOS (pmset). Das Format ist nicht dokumentiert; einzelne Einträge können fehlen.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            store.refreshBlockers()
            if !store.hasLoaded { Task { await store.refresh() } }
        }
    }

    @ViewBuilder
    private func sessionView(_ report: BGSleepReport) -> some View {
        let s = report.session
        VStack(alignment: .leading, spacing: 8) {
            Text(L("%@ – %@ (%@)", s.start.formatted(date: .abbreviated, time: .shortened),
                   s.end.formatted(date: .omitted, time: .shortened), Self.durationText(s.duration)))
                .font(.callout).monospacedDigit()
            Text(L("%lld %% → %lld %%: %lld Prozentpunkte, %.1f %%/h", s.startPercent, s.endPercent,
                   s.drainPoints, s.drainPerHour))
                .font(.title3.weight(.light)).monospacedDigit()
            if let baseline = report.baselinePerHour {
                Text(L("Üblich auf diesem Mac: %.1f %%/h", baseline)).font(.caption).foregroundStyle(.secondary)
            }
            if report.unusual {
                Label("Deutlich mehr Verbrauch als üblich. Häufige Ursachen: Power Nap, „Bei Netzwerkzugriff aufwachen“, Bluetooth-Geräte oder eine App, die den Schlaf verhindert.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text(L("Dunkles Aufwachen: %lld-mal", s.darkWakes)).font(.callout)
            ForEach(s.darkWakeReasons.prefix(3), id: \.reason) { item in
                Text(L("• %@ (%lld×)", Self.reasonText(item.reason), item.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }

    /// Übersetzt häufige Weckquellen aus dem Energieprotokoll; Unbekanntes bleibt im Original.
    static func reasonText(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("arpt") || lower.contains("wifi") || lower.contains("wlan") {
            return L("WLAN / Netzwerkwartung (%@)", raw)
        }
        if lower.contains("rtc") || lower.contains("maintenance") || lower.contains("sleepservice") {
            return L("geplante Wartung, z. B. Power Nap (%@)", raw)
        }
        if lower.contains("bluetooth") || lower.hasPrefix("bt") { return L("Bluetooth (%@)", raw) }
        if lower.contains("usb") { return L("USB-Gerät (%@)", raw) }
        if lower.contains("lid") { return L("Deckel geöffnet (%@)", raw) }
        if lower.contains("powerbutton") || lower.contains("pwrbtn") { return L("Ein-/Ausschalter (%@)", raw) }
        return raw
    }
}
