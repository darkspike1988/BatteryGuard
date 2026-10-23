import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BatteryGuardShared

/// Alle dauerhaften Einstellungen als JSON sichern und wiederherstellen.
struct SettingsBackupView: View {
    let configStore: ConfigStore
    @State private var message: String?

    /// Schlüssel, die nie in eine Sicherung gehören (Zeitstempel und Geheimnisse).
    static func isPortablePreference(_ key: String) -> Bool {
        let lower = key.lowercased()
        return key.hasPrefix("bg.") && !lower.contains("token") && !lower.contains("secret") && !key.hasSuffix("At")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Einstellungen sichern …") { export() }
                Button("Sicherung wiederherstellen …") { restore() }
            }
            Text("Enthält Ladegrenzen, Modus, Schutz, Automatik, Zeitpläne und App-Darstellung. Laufende Aufträge, Verläufe, Reisezeiten und der API-Token werden nicht gesichert.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption) }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "B-Guard-Einstellungen-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let preferences = UserDefaults.standard.dictionaryRepresentation()
            .filter { Self.isPortablePreference($0.key) }
            .compactMapValues(BGPreferenceValue.init)
        do {
            let backup = BGSettingsBackup(config: try configStore.savedConfig(), preferences: preferences)
            try BGJSON.encoder().encode(backup).write(to: url, options: .atomic)
            message = L("Einstellungen als %@ gesichert.", url.lastPathComponent)
        } catch { message = L("Sicherung fehlgeschlagen: %@", error.localizedDescription) }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try BGSettingsBackup.decode(Data(contentsOf: url))
            // Erst Zeitpläne über die Aktion anlegen: Bei ausstehender Speicherung lehnt performAPIAction ab.
            for task in backup.config.scheduledTasks {
                _ = try configStore.performAPIAction(.init(action: .upsertSchedule, scheduledTask: task))
            }
            configStore.config = configStore.config.applyingPortable(from: backup.config)
            for (key, value) in backup.preferences where Self.isPortablePreference(key) {
                UserDefaults.standard.set(value.value, forKey: key)
            }
            message = L("Sicherung vom %@ wiederhergestellt.", backup.createdAt.formatted(date: .abbreviated, time: .shortened))
        } catch { message = L("Wiederherstellung fehlgeschlagen: %@", error.localizedDescription) }
    }
}
