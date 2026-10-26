import SwiftUI
import AppKit

/// Netzteil-Angaben und Prozesse mit hoher Energiewirkung, nur bei sichtbarer Diagnoseseite.
/// Einziger Eingriff: eine App auf ausdrücklichen Wunsch normal beenden.
struct PowerDetailsView: View {
    @State private var adapter: BGAdapterInfo?
    @State private var consumers: [BGEnergyConsumer] = []
    @State private var sampledAt: Date?
    @State private var showSerial = false
    @AppStorage("energyImpactThreshold") private var threshold = 5.0
    @AppStorage("energyIncludeBackground") private var includeBackground = false
    @State private var quitCandidate: BGEnergyConsumer?

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
                Picker("Anzeigen ab", selection: $threshold) {
                    Text("Geringe Wirkung (ab 1)").tag(1.0)
                    Text("Mittlere Wirkung (ab 5)").tag(5.0)
                    Text("Hohe Wirkung (ab 20)").tag(20.0)
                }
                Toggle("Hintergrundprozesse einbeziehen", isOn: $includeBackground)
                if visibleConsumers.isEmpty {
                    Text(sampledAt == nil ? "Messung läuft …" : "Keine Prozesse mit nennenswerter Energiewirkung.").foregroundStyle(.secondary)
                } else {
                    ForEach(visibleConsumers) { consumer in
                        HStack {
                            LabeledContent(displayName(consumer), value: consumer.impact.formatted(.number.precision(.fractionLength(1))))
                            if let app = userApp(consumer) {
                                Button("Beenden") { quitCandidate = consumer }
                                    .controlSize(.small)
                                    .help(L("%@ normal beenden; ungesicherte Änderungen fragt die App selbst ab.", app.localizedName ?? consumer.name))
                            }
                        }
                    }
                }
                if let candidate = quitCandidate, let app = userApp(candidate) {
                    HStack {
                        Text(L("%@ beenden?", app.localizedName ?? candidate.name)).font(.callout)
                        Spacer()
                        Button("Abbrechen") { quitCandidate = nil }
                        Button("Beenden") {
                            app.terminate()
                            quitCandidate = nil
                        }.buttonStyle(.borderedProminent)
                    }
                }
                if let sampledAt {
                    Text(L("Gemessen um %@", sampledAt.formatted(date: .omitted, time: .standard)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Werte aus der Energiespalte von top über eine Sekunde: Apples relative Energiewirkung, keine Watt. Beenden schickt der App die normale Beenden-Anfrage. Prozessnamen erscheinen in keinem Export.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await refreshLoop() }
    }

    private var visibleConsumers: [BGEnergyConsumer] {
        consumers.filter { $0.impact >= threshold && (includeBackground || userApp($0) != nil) }
    }

    /// Nur sichtbare Apps des aktuellen Benutzers lassen sich beenden; B-Guard selbst nicht.
    private func userApp(_ consumer: BGEnergyConsumer) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid_t(consumer.pid)),
              app.activationPolicy == .regular, app != .current else { return nil }
        return app
    }

    private func displayName(_ consumer: BGEnergyConsumer) -> String {
        // `top` kürzt Namen auf 16 Zeichen; laufende Apps haben einen vollständigen Namen.
        NSRunningApplication(processIdentifier: pid_t(consumer.pid))?.localizedName ?? consumer.name
    }

    private func refreshLoop() async {
        guard !DesignPreview.isRendering else { return }
        while !Task.isCancelled {
            let (adapter, consumers) = await Task.detached(priority: .utility) {
                (PowerDetailsReader.readAdapter(), PowerDetailsReader.readEnergyConsumers(limit: 20))
            }.value
            self.adapter = adapter
            self.consumers = consumers
            sampledAt = Date()
            try? await Task.sleep(for: .seconds(10))
        }
    }
}
