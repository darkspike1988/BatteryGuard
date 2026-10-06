import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BatteryGuardShared

private enum DiagnosticQuestion: String, CaseIterable, Identifiable {
    case battery = "Akku hält kürzer", charging = "Lädt nicht", heat = "Mac wird heiß"
    case sleep = "Verliert Ladung im Schlaf", performance = "Mac ist langsam"
    var id: String { rawValue }
    var guidance: String {
        switch self {
        case .battery: "Vergleiche die gemeldeten Kapazitäten und Zyklen mit macOS. Für Laufzeitvergleiche Arbeit, Helligkeit und Anschluss gleich halten. Die Kapazitätsquote ist keine Lebensdauerprognose."
        case .charging: "Prüfe Netzteil, Kabel/Dock, Ladeprofil und Apples natives Limit. Ein gespeicherter Auftrag bestätigt noch keine Hardwarewirkung. Netzteil-Nennleistung und aktueller Energiefluss sind verschiedene Werte."
        case .heat: "Beobachte Systemthermik zusammen mit Last und Akkutemperatur. Hohe Arbeitslast kann normal sein. Systemthermik ist keine CPU-Temperaturmessung und nennt keine genaue Drosselungsquote."
        case .sleep: "Notiere Ladestand und Versorgung vor Schlaf und nach Wake. Die App zeichnet im Schlaf nicht auf. Eine Differenz allein trennt Schlaf, Aufwachphasen und zwischenzeitliches Laden nicht."
        case .performance: "Prüfe CPU-Last, RAM-Kategorien, Swap und verfügbaren Speicher. Ein einzelner Lastwert oder wenig freier RAM beweist keinen Defekt. Für weitere Details Aktivitätsanzeige verwenden."
        }
    }
}

struct DiagnosticsView: View {
    let statusStore: StatusStore
    @Bindable var history: HistoryStore
    @State private var question: DiagnosticQuestion = .battery
    @State private var exportMessage: String?

    private var battery: BGBatteryMeasurements { statusStore.status.diagnosticMeasurements() }
    private var system: BGSystemSnapshot? { statusStore.systemDiagnostics }
    private var issues: [BGDiagnosticIssue] { BGDiagnosticRules.evaluate(battery: battery, system: system, at: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BGSectionHeading(title: "Dein Mac, nachvollziehbar.", subtitle: DesignPreview.isRendering ? "Gerenderte Vorschau mit Beispieldaten." : "Messwerte mit Quelle, Zeitpunkt und Datenqualität.")
                BGPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Was möchtest du prüfen?", selection: $question) {
                            ForEach(DiagnosticQuestion.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Text(question.guidance).font(.callout).foregroundStyle(.secondary)
                        Button("Aktuellen Diagnosebericht exportieren") { exportReport() }
                        Text("Der Bericht enthält Messzeiten und Werte, aber keine Profile, Reisezeiten, Tokens, Seriennummern oder Prozessnamen.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let exportMessage { Text(exportMessage).font(.caption) }
                    }
                }
                BGPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Akku und Quellen").font(.headline)
                        diagnosticRow("Ladestand", metric: .chargePercent, in: battery)
                        diagnosticRow("Akkutemperatur", metric: .batteryTemperature, in: battery)
                        diagnosticRow("Zyklen", metric: .cycleCount, in: battery)
                        diagnosticRow("Gemeldete Maximal-Kapazität", metric: .fullChargeCapacity, in: battery)
                        diagnosticRow("Designkapazität", metric: .designCapacity, in: battery)
                        diagnosticRow("Kapazitätsquote", metric: .capacityRatio, in: battery)
                        if let reference = BGBatteryCycleReference.maximumCycles(model: system?.modelIdentifier) {
                            Text("Apple-Referenz für \(system?.modelIdentifier ?? "") : \(reference) Zyklen. Kein Countdown bis zum Ausfall.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Keine verifizierte modellbezogene Zyklusreferenz in B-Guard. Apples Modellliste prüfen.").font(.caption).foregroundStyle(.secondary)
                        }
                        Link("Apple: Zyklen und Modellgrenzen", destination: URL(string: "https://support.apple.com/102888")!)
                        Text("Apples Batteriezustand wird hier nicht aus dem Kapazitätsquotienten erraten. Vergleiche ihn in den Batterieeinstellungen.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Erfassungszeit ist der Zeitpunkt des Auslesens. Ein Firmware-Refresh ist nicht nachgewiesen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                BGPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Systemressourcen · rein lesend").font(.headline)
                        LabeledContent("Systemthermik", value: thermalText)
                        if let system, system.isFresh(at: Date()) {
                            diagnosticRow("CPU gesamt", metric: .cpuLoad, in: system.measurements)
                            diagnosticRow("RAM aktiv + verdrahtet + komprimiert", metric: .memoryUsed, in: system.measurements)
                            diagnosticRow("Physischer RAM", metric: .memoryTotal, in: system.measurements)
                            diagnosticRow("Swap belegt", metric: .swapUsed, in: system.measurements)
                            diagnosticRow("Volume verfügbar", metric: .volumeAvailable, in: system.measurements)
                            diagnosticRow("Volume gesamt", metric: .volumeTotal, in: system.measurements)
                            Text("RAM-Kategorien sind keine Speicherdruckmessung. Volumekapazität ist keine SSD-Gesundheitsdiagnose. CPU ist über das Messintervall gemittelt und auf alle Prozessoren normalisiert.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else { Text("Keine aktuellen Systemmesswerte.").foregroundStyle(.secondary) }
                        Text("Messung nur bei sichtbarer Diagnoseseite, höchstens alle zehn Sekunden über die bestehende Abfrage. SSD-Verschleiß, Lüfter, GPU-Leistung und Speicherdruck werden nicht erfasst.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                BGPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Beobachtungen und nächste Schritte").font(.headline)
                        ForEach(issues, id: \.rawValue) { issue in
                            Label(issueText(issue), systemImage: "info.circle")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Die Hinweise beschreiben verfügbare Daten. Sie belegen weder eine Ursache noch einen allgemein gesunden Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                BGPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kapazität über längere Zeit").font(.headline)
                        Toggle("Lokale Tageswerte bis zu zwölf Monate aufzeichnen", isOn: $history.longTermCapacityEnabled)
                        Text("Standardmäßig aus. Erfasst nur bei laufender App und gültigen Kapazitätsquellen. Deaktivieren pausiert die Aufzeichnung; vorhandene Werte bleiben erhalten.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = history.capacityError { Text(error).font(.caption).foregroundStyle(.orange) }
                        if let delta = BGCapacityTrend.change(history.capacityDays) {
                            Text(String(format: "Beobachtete Veränderung: %+.1f Prozentpunkte", delta))
                            Text("Vergleich erster und letzter Tagesmittelwerte gleicher Quelle, Designkapazität und OS-Version; keine Alterungsprognose.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Trend noch nicht vergleichbar: mindestens drei Tageswerte gleicher Quellen und Systemversion nötig.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(Array(history.capacityDays.sorted { $0.lastSampledAt > $1.lastSampledAt }.prefix(7))) { day in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(utcDayText(day.day))
                                    Spacer()
                                    Text(String(format: "%.1f %% · %d Messungen", day.mean, day.count)).monospacedDigit()
                                }
                                Text(String(format: "Spanne %.1f–%.1f %% · UTC-Tag · keine ganztägige Messabdeckung", day.minimum, day.maximum))
                                    .foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                    }
                }
            }.padding(28).frame(maxWidth: 900)
        }
        .onAppear { statusStore.beginDiagnostics() }
        .onDisappear { statusStore.endDiagnostics() }
    }

    private func utcDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func diagnosticRow(_ title: String, metric: BGMetric, in data: BGBatteryMeasurements) -> some View {
        let item = data.measurement(metric)
        return VStack(alignment: .leading, spacing: 3) {
            LabeledContent(title, value: formatted(item))
            Text(item.map { "\(sourceText($0.source)) · \(qualityText($0.quality)) · \($0.sampledAt.formatted(date: .omitted, time: .standard))" } ?? "Keine Quelle verfügbar")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func qualityText(_ quality: BGMeasurementQuality) -> String {
        switch quality {
        case .reported: "gemeldet"
        case .derived: "berechnet"
        case .unavailable: "nicht verfügbar"
        case .unsupported: "nicht unterstützt"
        case .invalid: "ungültig"
        case .stale: "veraltet"
        }
    }

    private func sourceText(_ source: BGMeasurementSource) -> String {
        switch source {
        case .powerSources: "macOS-Stromquellen"
        case .registryCharge: "Akku-Registry: Ladekapazitäten"
        case .registryTemperature: "Akku-Registry: Temperatur"
        case .registryCycles: "Akku-Registry: Zyklen"
        case .rawMaxCapacity: "Akku-Registry: Roh-Maximalkapazität"
        case .fullChargeCapacity: "Akku-Daten: Vollladekapazität"
        case .nominalCapacity: "Akku-Daten: Nennkapazität"
        case .designCapacity: "Akku-Registry: Designkapazität"
        case .nestedDesignCapacity: "Akku-Daten: Designkapazität"
        case .registryPower: "Akku-Registry: Spannung und Strom"
        case .smcTemperature: "Akku-Sensor über SMC"
        case .capacityCalculation: "Maximal- / Designkapazität"
        case .legacyStatus: "Status: Herkunft unbekannt"
        case .machCPU: "macOS: CPU-Zeitanteile"
        case .machMemory: "macOS: Speicherkategorien"
        case .swapUsage: "macOS: Swap-Belegung"
        case .volumeCapacity: "macOS: Volumekapazität"
        }
    }

    private func formatted(_ item: BGMeasurement?) -> String {
        guard let item, let value = item.value else { return "Nicht verfügbar" }
        if item.unit == "bytes" { return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
        if item.metric == .cycleCount { return String(format: "%.0f", value) }
        return String(format: "%.1f %@", value, item.unit)
    }

    private var thermalText: String {
        guard let system, system.isFresh(at: Date()) else { return "Nicht verfügbar" }
        switch system.thermalState {
        case .nominal: return "Normal laut macOS"
        case .fair: return "Leicht erhöht laut macOS"
        case .serious: return "Deutlich erhöht laut macOS"
        case .critical: return "Kritisch laut macOS"
        case .unknown: return "Unbekannt"
        }
    }

    private func issueText(_ issue: BGDiagnosticIssue) -> String {
        switch issue {
        case .batteryDataUnavailable: "Kein aktueller Akkustand. Dienst und Messquellen prüfen; daraus folgt keine Entwarnung."
        case .capacityIsEstimate: "Kapazitätsquote ist berechnet und kann von Apples Anzeige abweichen. Einzelne Schwankungen sind kein nachgewiesener Verschleiß."
        case .legacySourceUnknown: "Älterer Dienst: Herkunft einzelner Werte unbekannt. Für den neuen Quellenvertrag den Dienst aktualisieren."
        case .systemDataUnavailable: "Keine aktuellen Systemdaten. Eine umfassende Mac-Bewertung ist nicht möglich."
        case .thermalElevated: "macOS meldet deutlich erhöhte Systemthermik. Normale Arbeitslast prüfen und unnötige Last verringern; keine Defektdiagnose."
        case .thermalCritical: "macOS meldet kritische Systemthermik. Arbeit reduzieren und den Mac abkühlen lassen."
        case .cpuBusy: "CPU im letzten Messintervall stark ausgelastet. Aktivitätsanzeige prüfen; hohe Last allein ist kein Fehler."
        case .volumeCapacityUnavailable: "Verfügbare Volumekapazität unbekannt. Keine Aussage zum Speicherplatz möglich."
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "B-Guard-Messbericht.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = BGDiagnosticReport(appVersion: AppVersion.installed, daemonVersion: statusStore.status.daemonVersion,
                                            battery: statusStore.status, system: system, capacityDays: history.capacityDays, at: Date())
            try BGJSON.encoder().encode(report).write(to: url, options: .atomic)
            exportMessage = "Messbericht gespeichert."
        } catch { exportMessage = "Messbericht konnte nicht gespeichert werden." }
    }
}
