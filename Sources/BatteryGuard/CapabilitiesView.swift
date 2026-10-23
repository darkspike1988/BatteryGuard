import SwiftUI
import BatteryGuardShared

/// Welche Steuerwege dieser Mac mit der aktuellen Firmware anbietet.
struct CapabilitiesView: View {
    let status: BGStatus

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fähigkeiten dieses Macs").font(.headline)
                if let capabilities = status.capabilities {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                        row("System-Firmware", capabilities.firmwareVersion ?? L("unbekannt"))
                        row("macOS", capabilities.macOSVersion ?? L("unbekannt"))
                        row("SMC-Ladesperre", availability(capabilities.chargeLockKeys))
                        row("Netzteil-Schalter", availability(capabilities.adapterSwitchKeys))
                        row("macOS-Limit", capabilities.systemChargeLimits.isEmpty ? L("nicht verfügbar")
                            : capabilities.systemChargeLimits.map { "\($0)" }.joined(separator: " · ") + " %")
                        row("MagSafe-LED", capabilities.magSafeLED ? L("verfügbar") : L("nicht verfügbar"))
                        row("High Power Mode", capabilities.highPowerMode ? L("verfügbar") : L("nicht verfügbar"))
                        row("Apple-Kalibrierung", status.appleCalibrationActive == true ? L("läuft gerade") : L("nicht aktiv"))
                    }
                    if let change = status.capabilityChange {
                        Label(L("Seit %@ geändert: %@", change.detectedAt.formatted(date: .abbreviated, time: .shortened),
                                change.changes.map(StatusMessageLocalizer.localized).joined(separator: "; ")),
                              systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    Text("Ob eine Ladesteuerung funktioniert, hängt von der Firmware ab, nicht nur von der macOS-Version. Nach Updates prüft der Dienst die Fähigkeiten neu.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Der Dienst hat noch keine Fähigkeiten gemeldet.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func availability(_ keys: [String]) -> String {
        keys.isEmpty ? L("nicht verfügbar") : L("verfügbar (%@)", keys.joined(separator: ", "))
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
