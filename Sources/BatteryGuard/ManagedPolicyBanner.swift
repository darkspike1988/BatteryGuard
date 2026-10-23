import SwiftUI
import BatteryGuardShared

/// Zeigt, welche Werte die IT per Konfigurationsprofil vorgibt.
struct ManagedPolicyBanner: View {
    let policy: BGManagedPolicy

    private var details: String {
        var parts: [String] = []
        if let upper = policy.upperLimit { parts.append(L("Ladeziel %lld %%", upper)) }
        if let lower = policy.lowerLimit { parts.append(L("untere Grenze %lld %%", lower)) }
        if let mode = policy.mode { parts.append(L("Modus %@", mode.localizedName)) }
        if let enabled = policy.protectionEnabled { parts.append(enabled ? L("Schutz an") : L("Schutz aus")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(policy.lockSettings ? "Von deiner IT verwaltet und gesperrt" : "Von deiner IT vorgegeben").font(.headline)
                if !details.isEmpty { Text(details).font(.callout) }
                Text("Die Vorgaben stammen aus einem Konfigurationsprofil und gelten unabhängig von den Einstellungen hier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "building.2")
        }
    }
}
