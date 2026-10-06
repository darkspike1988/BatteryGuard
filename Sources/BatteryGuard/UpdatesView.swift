import SwiftUI
import AppKit

struct ChangeEntry: Identifiable {
    var id: String { version }
    let version: String
    let title: String
    let changes: [String]
    static let history: [ChangeEntry] = [
        .init(version: "0.3.8", title: "Gespeicherte Profile schützen", changes: [
            "Gleichzeitige Profiländerungen werden erkannt, statt neuere Daten zu überschreiben.",
            "Profile direkt neu laden; Lesefehler von beschädigten Daten unterscheiden.",
            "Import sichert den vorherigen Stand unter derselben Dateisperre. Export nach einem Lesefehler meldet einen Fehler.",
            "Hintergrunddienst 0.3.7 bleibt erforderlich. Hardware- und Systemabnahmen bleiben offen."
        ]),
        .init(version: "0.3.7", title: "Eigene Profile und Zeitpläne", changes: [
            "Benannte Profile mit Bearbeiten, Importvorschau, Sicherung und Export.",
            "Wiederkehrende Aufgaben im Hintergrunddienst mit Zeitzone, Sommerzeit, manueller Übersteuerung und Verlauf.",
            "Top Up bis Abstecken bei separater Ladesteuerung; neue Halte-, Entlade- und Kalibrierungsaktionen bleiben bis zur Hardware-Abnahme gesperrt.",
            "Experimentelle steuernde Kurzbefehle, nächste Aufgabe im Menü und kombinierte Messanzeigen.",
            "Optional bis zum Limit wachhalten, höchstens zwei Stunden; Diagnoseexport ohne persönliche Daten.",
            "Hitzeschutz und konkurrierende Aufträge korrigiert. Hintergrunddienst 0.3.7 erforderlich. System- und Hardware-Abnahmen bleiben offen."
        ]),
        .init(version: "0.3.6", title: "Deine Menükarten", changes: [
            "Messwerte, Energiefluss und Verlauf in eigener Reihenfolge im Menüfenster anzeigen.",
            "Kompakte Darstellung wählen; letzte Verlaufsmessung mit eindeutigem Zeitpunkt.",
            "Experimentelle lesende Kurzbefehle für Akkustatus und Energiefluss als JSON.",
            "Darstellung separat zurücksetzen. Hintergrunddienst 0.3.2 bleibt ausreichend."
        ]),
        .init(version: "0.3.5", title: "Energiefluss verstehen", changes: [
            "Netzteil-Eingang, geschätzte Mac-Leistung und Akku-Ladefluss getrennt anzeigen.",
            "Energiefluss als optionale Karte im Menüfenster; fehlende Messwerte bleiben unbekannt.",
            "Lesender REST-Endpunkt /api/v1/power-flow und JSON-Abfrage für eigene Automatisierung.",
            "Netzteil-Nennleistung und Hardware-Ladestand nur bei verfügbaren Daten. Dienst 0.3.2 bleibt ausreichend."
        ]),
        .init(version: "0.3.4", title: "Dein Symbolstil", changes: [
            "Monochrome Symbolstile: Ladering, Batterie oder Schild.",
            "Darstellung zurücksetzen, ohne Ladeprofil, Mitteilungen, API oder Autostart zu verändern.",
            "Netzteilversorgung, tatsächliches Laden und Entladen in der Statusanzeige unterscheiden.",
            "Hintergrunddienst 0.3.2 weiterhin ausreichend."
        ]),
        .init(version: "0.3.3", title: "Deine Menüleiste", changes: [
            "Menüleistenanzeige wählen: Symbol, Prozent, Akkutemperatur oder Akku-Leistung.",
            "Temperatur, Akku-Leistung und Gesundheit optional direkt im Menüfenster anzeigen.",
            "Niedrigen Akkustand unabhängig vom Ladeprofil melden: einstellbare Warnschwelle von 5 bis 50 %, standardmäßig 20 %.",
            "0 W verständlich erklärt: Akkustrom und gesamter Mac-Verbrauch sind unterschiedliche Messwerte.",
            "UTF-8-JSON für REST-Aktionen; übergroße Update-Downloads während des Transfers abbrechen.",
            "Kein erneutes Dienstupdate nötig, wenn Dienst 0.3.2 bereits installiert ist."
        ]),
        .init(version: "0.3.2", title: "Zuverlässige Ladebefehle", changes: [
            "API-Aktionen werden atomar auf den neuesten gespeicherten Zustand angewandt.",
            "Ein alter Volllade-Abschluss kann neu gestartetes Vollladen oder einen neuen Reiseplan nicht mehr löschen.",
            "Eindeutige Anforderungs-IDs schützen auch erneute Befehle innerhalb derselben Sekunde.",
            "Hintergrunddienst 0.3.2 erforderlich; alte Dienste lehnen neue API-Befehle eindeutig ab."
        ]),
        .init(version: "0.3.1", title: "Lokale Automatisierung", changes: [
            "Optionale REST API: Status, gespeicherte Einstellungen und Verlauf als JSON oder CSV auslesen.",
            "Profile, Schutzpausen, Vollladen und Reiseplanung per separat freigegebenen Steuerbefehlen.",
            "Lokaler Bearer-Token mit Erneuerung, begrenzte Anfragen und Schutz vor widersprüchlichen offenen Änderungen.",
            "App-Update ohne erneute Installation des Hintergrunddienstes 0.3.0."
        ]),
        .init(version: "0.3.0", title: "Zuverlässiger im Alltag", changes: [
            "Zukünftige Reisepläne bleiben beim Beenden manuellen Vollladens erhalten; einheitliche Ladegrenzen und klarere Monitor-Anzeige.",
            "Beschädigten Verlauf sichern und weiter aufzeichnen; Uhrzeitkorrekturen blockieren keine neuen Messpunkte.",
            "Hitzeschutz mit 2 °C Abkühlung vor Wiederfreigabe und stabiler Akkureserve; Monitoränderungen unmittelbar prüfen.",
            "Hardwarezustand regelmäßig nachlesen; Einstellungen über authentifizierte lokale Dienstkommunikation speichern.",
            "Updatefortschritt und Abbrechen, sichtbare Mitteilungsfreigabe und zugängliche Verlaufsauswahl."
        ]),
        .init(version: "0.2.3", title: "Updates & Neuigkeiten", changes: [
            "Automatische Updateprüfung höchstens täglich über GitHub, abschaltbar und ohne Konto.",
            "DMG direkt laden, per SHA-256 prüfen und öffnen.",
            "Neue Versionen mit Änderungen und Verbesserungen in der App anzeigen; Changelog auch offline verfügbar.",
            "App-Updates verlangen nur dann ein Dienstupdate, wenn dessen Funktionen tatsächlich benötigt werden."
        ]),
        .init(version: "0.2.2", title: "Hallo, B-Guard", changes: [
            "Neuer Name für App und DMG; Einstellungen und Verlauf bleiben erhalten.",
            "Gemeinsame Dateisperren und Zusammenführen paralleler Einstellungsänderungen.",
            "Ladesteuerung vor dem Schlafen freigeben und nach dem Aufwachen neu prüfen.",
            "Akkuleistung verständlicher erklärt; einzelne Verlaufspunkte nach Lücken bleiben sichtbar.",
            "Neue kostenlose Open-Source-Website mit direktem DMG-Download."
        ]),
        .init(version: "0.2.1", title: "Externer Monitor", changes: [
            "Netzteil bleibt bei externem Monitor oder geschlossenem Deckel verbunden.",
            "Keine System-Schlafsperre durch B-Guard mehr.",
            "Ohne separate Ladesperre übernimmt macOS im Monitorbetrieb das Limit."
        ]),
        .init(version: "0.2.0", title: "Ein Akkuplan für deinen Alltag", changes: [
            "Ladeprofile, Reiseplanung, zeitliche Schutzpausen und einmaliges Vollladen.",
            "Sieben Tage lokaler Messverlauf mit Temperatur, Leistung, Auswertung und CSV-Export.",
            "Native macOS-Oberfläche, grauweißes Icon und DMG-Installation.",
            "Verbesserte Hardware-Erkennung, Fehleranzeigen und Regressionstests."
        ])
    ]
}

struct UpdatesView: View {
    @Bindable var updates: UpdateStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BGSectionHeading(title: "Updates & Neuigkeiten", subtitle: "B-Guard bleibt in Bewegung.")
                BGPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Installierte App", value: updates.currentVersion)
                        LabeledContent("Erforderlicher Dienst für diese App", value: AppVersion.requiredDaemon)
                        if let release = updates.release {
                            LabeledContent("Aktuelle Veröffentlichung", value: release.version)
                        }
                        if updates.isDownloading {
                            ProgressView(value: Double(updates.downloadBytes), total: Double(max(1, updates.downloadTotal)))
                            HStack {
                                Text("\(ByteCountFormatter.string(fromByteCount: updates.downloadBytes, countStyle: .file)) von \(ByteCountFormatter.string(fromByteCount: updates.downloadTotal, countStyle: .file))")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                Spacer()
                                Button("Download abbrechen") { updates.cancelDownload() }
                            }
                        }
                        HStack {
                            Button(updates.isChecking ? "Wird geprüft …" : "Nach Updates suchen") {
                                Task { await updates.check() }
                            }.disabled(updates.isChecking || updates.isDownloading)
                            if updates.updateAvailable {
                                Button(updates.isDownloading ? "Wird geladen …" : "Update laden und öffnen") {
                                    Task { await updates.downloadAndOpen() }
                                }.buttonStyle(.borderedProminent)
                                    .disabled(updates.isChecking || updates.isDownloading || updates.release?.safeDownload == nil)
                            }
                            if updates.isChecking || updates.isDownloading { ProgressView().controlSize(.small) }
                        }
                        if let message = updates.message {
                            Text(message).font(.callout).foregroundStyle(updates.isError ? Color.orange : Color.secondary)
                                .textSelection(.enabled)
                        }
                        if let checked = updates.checkedAt {
                            Text("Zuletzt erfolgreich geprüft: \(checked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let downloaded = updates.downloadedURL {
                            Button("Download im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([downloaded]) }
                        }
                        Link("Veröffentlichungen auf GitHub ↗", destination: URL(string: "https://github.com/darkspike1988/BatteryGuard/releases")!)
                        Toggle("Automatisch nach Updates suchen", isOn: $updates.automaticChecksEnabled)
                        Text("Die automatische Prüfung kontaktiert GitHub höchstens täglich und lässt sich abschalten. Manuelle Prüfungen sind jederzeit möglich. Der Download bleibt eine DMG: App beenden, auf Programme ziehen und ersetzen. Deine Einstellungen und dein Verlauf bleiben erhalten.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let release = updates.release, updates.updateAvailable, let body = release.body, !body.isEmpty {
                    BGPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Neu in \(release.version)").font(.headline)
                            Text(body).font(.callout).textSelection(.enabled)
                        }
                    }
                }
                Text("Versionshistorie").font(.title2.weight(.semibold))
                ForEach(ChangeEntry.history) { entry in
                    BGPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(entry.title).font(.headline)
                                Spacer()
                                Text(entry.version).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            ForEach(entry.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(change).font(.callout).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }.padding(28).frame(maxWidth: 740)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
