import SwiftUI
import CoreLocation
import BatteryGuardShared

/// Ladeprofile je WLAN, zum Beispiel Büro → Schreibtisch, unterwegs → Unterwegs.
struct NetworkRulesView: View {
    @State private var monitor = NetworkRuleMonitor.shared
    @State private var rules = NetworkRuleMonitor.shared.rules
    @State private var newProfile: BGProfile = .desk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rules) { rule in
                HStack {
                    Text(rule.ssid)
                    Spacer()
                    Text(rule.profile.localizedTitle).foregroundStyle(.secondary)
                    Button("Regel löschen", systemImage: "trash", role: .destructive) {
                        rules.removeAll { $0.id == rule.id }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            switch monitor.authorization {
            case .authorizedAlways, .authorized:
                HStack {
                    Picker("Profil", selection: $newProfile) {
                        ForEach(BGProfile.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    .fixedSize()
                    Button(monitor.currentSSID.map { L("„%@“ hinzufügen", $0) } ?? L("Aktuelles WLAN hinzufügen")) { addCurrent() }
                        .disabled(rules.count >= BGNetworkRules.maxRules)
                }
            case .denied, .restricted:
                Text("Ohne Standortfreigabe nennt macOS keinen WLAN-Namen. Freigabe in Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste.")
                    .font(.caption).foregroundStyle(.orange)
            default:
                Button("WLAN-Regeln aktivieren") { monitor.requestAuthorization() }
            }
            Text("Wechselt der Mac in ein WLAN mit Regel, wählt B-Guard das Profil; wie eine manuelle Wahl pausiert das Zeitpläne für zwei Stunden. Der WLAN-Name bleibt auf diesem Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: rules) { _, updated in monitor.rules = updated }
    }

    private func addCurrent() {
        monitor.poll(force: true) { _ in false }
        guard let ssid = monitor.currentSSID, !ssid.isEmpty else { return }
        rules.removeAll { $0.ssid == ssid }
        rules.append(BGNetworkRule(ssid: ssid, profile: newProfile))
    }
}
