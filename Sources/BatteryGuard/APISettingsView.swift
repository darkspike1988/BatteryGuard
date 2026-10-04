import SwiftUI
import AppKit

struct APISettingsView: View {
    @Bindable var api: LocalAPIStore
    var body: some View {
        Section {
            Toggle("Lokale REST API aktivieren", isOn: Binding(get: { api.enabled }, set: { api.setEnabled($0) }))
            if api.enabled {
                LabeledContent("Status", value: api.running ? "Bereit" : (api.isError ? "Nicht verfügbar" : "Wird gestartet …"))
                Text(api.address).font(.caption.monospaced()).textSelection(.enabled)
                Toggle("Steuerbefehle über API erlauben", isOn: $api.allowsControl)
                HStack {
                    Button("API-Token kopieren") { api.copyToken() }
                    Button("Token erneuern") { api.rotateToken() }
                }
                if !api.running {
                    Button("Erneut starten") { api.setEnabled(true) }
                }
            }
            if let message = api.message {
                Text(message).font(.caption).foregroundStyle(api.isError ? Color.orange : Color.secondary)
            }
            Text("Nur auf diesem Mac, mit API-Token und bei laufender App. Status, Einstellungen und Verlauf sind lesbar. Steuerbefehle benötigen eine zusätzliche Freigabe; der Hintergrunddienst prüft weiterhin deine Benutzerrechte.")
                .font(.caption).foregroundStyle(.secondary)
            Link("API-Dokumentation und Beispiele ↗", destination: URL(string: "https://github.com/darkspike1988/BatteryGuard/blob/main/docs/api.md")!)
        } header: { Text("Automatisierung") }
    }
}
