import SwiftUI
import AppKit

/// Netzteil-Angaben und Prozesse mit hoher Energiewirkung. Rein lesend und nur bei sichtbarer Diagnoseseite.
struct PowerDetailsView: View {
    @State private var adapter: BGAdapterInfo?
    @State private var consumers: [BGEnergyConsumer] = []
    @State private var sampledAt: Date?
    @State private var showSerial = false

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Netzteil · rein lesend").font(.headline)
                if let adapter {
                    if let name = adapter.name { LabeledContent("Bezeichnung", value: name) }
                    if let manufacturer = adapter.manufacturer { LabeledContent("Hersteller", value: manufacturer) }
                    if let watts = adapter.ratedWatts { LabeledContent("Nennleistung", value: L("%lld W", Int(watts.rounded()))) }
                    if let voltage = adapter.voltage, let current = adapter.current {
                        LabeledContent("Ausgehandeltes Profil", value: L("%@ V · %@ A", voltage.formatted(.number.precision(.fractionLength(1))), current.formatted(.number.precision(.fractionLength(2)))))
                    }
                    if let firmware = adapter.firmwareVersion { LabeledContent("Firmware", value: firmware) }
                    if let serial = adapter.serialNumber {
                        LabeledContent("Seriennummer") {
                            Button(showSerial ? serial : L("Anzeigen")) { showSerial.toggle() }.buttonStyle(.link)
                        }
                    }
                    Text("Nennwerte beschreiben das ausgehandelte Ladeprofil, nicht den aktuellen Verbrauch. Die Seriennummer bleibt lokal und erscheint in keinem Export.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Kein Netzteil gemeldet.").foregroundStyle(.secondary)
                }
            }
        }
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hohe Energiewirkung").font(.headline)
                if consumers.isEmpty {
                    Text(sampledAt == nil ? "Messung läuft …" : "Keine Prozesse mit nennenswerter Energiewirkung.").foregroundStyle(.secondary)
                } else {
                    ForEach(consumers) { consumer in
                        LabeledContent(displayName(consumer), value: consumer.impact.formatted(.number.precision(.fractionLength(1))))
                    }
                }
                if let sampledAt {
                    Text(L("Gemessen um %@", sampledAt.formatted(date: .omitted, time: .standard)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Werte aus der Energiespalte von top über eine Sekunde: Apples relative Energiewirkung, keine Watt. Enthält auch Hintergrunddienste. Prozessnamen erscheinen in keinem Export.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await refreshLoop() }
    }

    private func displayName(_ consumer: BGEnergyConsumer) -> String {
        // `top` kürzt Namen auf 16 Zeichen; laufende Apps haben einen vollständigen Namen.
        NSRunningApplication(processIdentifier: pid_t(consumer.pid))?.localizedName ?? consumer.name
    }

    private func refreshLoop() async {
        guard !DesignPreview.isRendering else { return }
        while !Task.isCancelled {
            let (adapter, consumers) = await Task.detached(priority: .utility) {
                (PowerDetailsReader.readAdapter(), PowerDetailsReader.readEnergyConsumers())
            }.value
            self.adapter = adapter
            self.consumers = consumers
            sampledAt = Date()
            try? await Task.sleep(for: .seconds(10))
        }
    }
}
