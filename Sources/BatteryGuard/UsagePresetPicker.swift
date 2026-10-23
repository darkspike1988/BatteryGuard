import SwiftUI
import BatteryGuardShared

/// Schlägt nach der Einrichtung ein Ladeprofil passend zur Nutzung vor; übernimmt es erst nach Bestätigung.
struct UsagePresetPicker: View {
    @State private var preset: UsagePreset = .mixed
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wie nutzt du deinen Mac meistens?").font(.headline)
            Picker("Nutzung", selection: $preset) {
                ForEach(UsagePreset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(L("Vorschlag: %@ (%lld–%lld %%)", preset.profile.localizedTitle, preset.profile.lower, preset.profile.upper))
                .font(.callout).foregroundStyle(.secondary)
            Button("Profil übernehmen") { apply() }
            if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func apply() {
        do {
            _ = try BGConfigClient.performAction(.init(action: .profile, profile: preset.profile.rawValue))
            result = L("Profil übernommen. Du kannst es jederzeit in der Menüleiste ändern.")
        } catch {
            result = error.localizedDescription
        }
    }
}
