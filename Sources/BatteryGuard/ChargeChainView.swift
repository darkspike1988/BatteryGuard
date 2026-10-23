import SwiftUI
import BatteryGuardShared

/// Prüft Netzteil, Kabel und Dock anhand der ausgehandelten Leistung.
struct ChargeChainView: View {
    let statusStore: StatusStore
    @State private var adapter: BGAdapterDetails?
    @State private var memory = Self.loadMemory()
    private static let memoryKey = "bg.adapterMemory"

    private var findings: [BGChargeChainFinding] {
        BGChargeChainCheck.evaluate(adapter: adapter, status: statusStore.status,
                                    batteryWatts: statusStore.powerFlow?.batteryWatts ?? statusStore.status.watts,
                                    bestKnownWatts: memory.best(for: adapter))
    }

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ladekette: Netzteil, Kabel, Dock").font(.headline)
                if statusStore.status.pluggedIn, let adapter {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                        GridRow {
                            Text("Netzteil").font(.callout).foregroundStyle(.secondary)
                            Text(adapter.name ?? "—").font(.callout)
                        }
                        GridRow {
                            Text("Ausgehandelt").font(.callout).foregroundStyle(.secondary)
                            Text(adapter.negotiatedWatts.map { L("%lld W", $0) } ?? "—").font(.callout).monospacedDigit()
                        }
                        if let offered = adapter.offeredMaxWatts {
                            GridRow {
                                Text("Vom Netzteil angeboten").font(.callout).foregroundStyle(.secondary)
                                Text(L("%lld W", offered)).font(.callout).monospacedDigit()
                            }
                        }
                    }
                } else if !statusStore.status.pluggedIn {
                    Text("Kein Netzteil angeschlossen.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    let text = Self.text(for: finding)
                    Label(text, systemImage: Self.isProblem(finding) ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(Self.isProblem(finding) ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: statusStore.status.pluggedIn) { refresh() }
    }

    private func refresh() {
        adapter = statusStore.status.pluggedIn ? PowerFlowReader.readAdapter() : nil
        let next = memory.observing(adapter)
        guard next != memory else { return }
        memory = next
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: Self.memoryKey) }
    }

    private static func loadMemory() -> BGAdapterMemory {
        guard let data = UserDefaults.standard.data(forKey: memoryKey),
              let memory = try? JSONDecoder().decode(BGAdapterMemory.self, from: data) else { return BGAdapterMemory() }
        return memory
    }

    private static func isProblem(_ finding: BGChargeChainFinding) -> Bool {
        if case .ok = finding { return false }
        return true
    }

    static func text(for finding: BGChargeChainFinding) -> String {
        switch finding {
        case .cableOrDockLimit(let negotiated, let offered):
            return L("Das Netzteil bietet bis zu %lld W, ausgehandelt sind nur %lld W. Meist begrenzt ein 3-A-Kabel oder ein Dock. Für mehr als 60 W braucht es ein USB-C-Kabel mit 5 A (100 W oder 240 W).", offered, negotiated)
        case .lowerThanBefore(let negotiated, let best):
            return L("Dieses Netzteil lieferte früher %lld W, jetzt %lld W. Wahrscheinlich hängt ein anderes Kabel oder Dock dazwischen.", best, negotiated)
        case .weakAdapter(let watts):
            return L("Schwaches Netzteil (%lld W). Laden dauert lange, und unter Last kann der Akku trotz Netzteil sinken.", watts)
        case .drainingWhilePlugged(let watts):
            return L("Der Akku entlädt sich trotz Netzteil (%.1f W). Netzteil oder Kabel reichen für die aktuelle Last nicht aus.", watts)
        case .flapping(let count):
            return L("Das Netzteil wurde in der letzten Stunde %lld-mal getrennt und verbunden. Prüfe Stecker, Kabel und Dock auf Wackelkontakt.", count)
        case .ok(let negotiated):
            return negotiated.map { L("Ladekette in Ordnung: %lld W ausgehandelt.", $0) } ?? L("Keine Auffälligkeiten erkannt.")
        }
    }
}
