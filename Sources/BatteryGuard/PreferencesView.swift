import SwiftUI
import AppKit
import BatteryGuardShared

struct PreferencesView: View {
    @Bindable var statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    @Bindable var services: ServiceManager
    @Bindable private var presence = AppPresence.shared
    @State private var confirmUninstall = false
    @AppStorage("bg.notifyLow") private var notifyLow = true
    @AppStorage("bg.notifyLimit") private var notifyLimit = false
    @AppStorage("bg.notifyHeat") private var notifyHeat = true

    private var canConfigure: Bool { configStore.config.mode != .native && configStore.config.mode != .direct }

    var body: some View {
        Form {
            Section {
                Picker("Ladesteuerung", selection: $configStore.config.mode) {
                    Text("Automatisch").tag(BGMode.auto)
                    Text("macOS · nur beobachten").tag(BGMode.native)
                    Text("Pendel · Netzteil umschalten").tag(BGMode.pendulum)
                    if configStore.config.mode == .direct { Text("Direkt · nicht verfügbar").tag(BGMode.direct) }
                }
                if let limit = statusStore.status.nativeChargeLimit, statusStore.isDaemonActive {
                    LabeledContent("Erkanntes macOS-Limit", value: "\(limit) %")
                }
                Text(configStore.config.mode.description).font(.caption).foregroundStyle(.secondary)
                if configStore.config.mode == .native {
                    Button("macOS-Batterieeinstellungen öffnen") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
                    }
                } else {
                    Toggle("Ladeschutz aktiv", isOn: $configStore.config.enabled)
                    Stepper("Laden ab \(configStore.config.lowerLimit) %", value: $configStore.config.lowerLimit,
                            in: 5...max(5, configStore.config.upperLimit - 5))
                    Stepper("Stoppen bei \(configStore.config.upperLimit) %", value: $configStore.config.upperLimit,
                            in: max(20, configStore.config.lowerLimit + 5)...100)
                    Text("Im Pendelmodus verbindet sich das Netzteil bei Maximum minus 5 % wieder. Die untere Grenze bleibt die Sicherheitsgrenze des Hitzeschutzes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Ladebereich") }

            Section {
                Toggle("Bei Wärme das Laden pausieren", isOn: Binding(
                    get: { configStore.config.heatProtectionCelsius > 0 },
                    set: { configStore.config.heatProtectionCelsius = $0 ? 40 : 0 }
                ))
                if configStore.config.heatProtectionCelsius > 0 {
                    Stepper("Temperaturgrenze \(configStore.config.heatProtectionCelsius) °C",
                            value: $configStore.config.heatProtectionCelsius, in: 30...50)
                }
                Toggle("Oberhalb des Limits aktiv entladen", isOn: $configStore.config.activeDischargeAboveUpper)
                Text("Aktives Entladen trennt das Netzteil softwareseitig. Im Pendelmodus geschieht dies bereits automatisch. Hitzeschutz bleibt beim Vollladen aktiv, während einer Schutzpause jedoch ausgesetzt.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("MagSafe-Farbe dem Ladezustand anpassen", isOn: $configStore.config.magsafeLed)
                    .help("Funktioniert nur, wenn die Hardware den LED-Schlüssel unterstützt.")
            } header: { Text("Schutz") }
                .disabled(!canConfigure)

            Section {
                Toggle("Bei niedrigem Akkustand", isOn: $notifyLow)
                Toggle("Beim Erreichen des Ladelimits", isOn: $notifyLimit)
                Toggle("Bei hoher Akkutemperatur", isOn: $notifyHeat)
                Button("Mitteilungen erlauben") { NotificationManager.shared.requestAuthorization() }
                Text("Mitteilungen werden nur aus aktuellen Messwerten erzeugt. Die Freigabe verwaltest du auch in den macOS-Systemeinstellungen.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Mitteilungen") }

            Section {
                Toggle("Beim Anmelden starten", isOn: $presence.launchAtLogin)
                Toggle("Im Dock anzeigen", isOn: $presence.showInDock)
                if presence.launchAtLoginNeedsApproval {
                    Button("Autostart in Systemeinstellungen erlauben") { presence.openLoginItemsSettings() }
                }
                if let error = presence.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            } header: { Text("App") }

            Section {
                LabeledContent("Status", value: statusStore.isDaemonActive ? "Verbunden" : "Nicht erreichbar")
                LabeledContent("Dienstversion", value: statusStore.isDaemonActive ? statusStore.status.daemonVersion : "—")
                if statusStore.isDaemonActive {
                    LabeledContent("Ladezyklen", value: statusStore.status.cycleCount.map(String.init) ?? "—")
                    LabeledContent("SMC-Unterstützung", value: statusStore.status.smcKeysDetected.joined(separator: ", "))
                }
                HStack {
                    Button(statusStore.isDaemonActive ? "Dienst aktualisieren" : "Dienst installieren") { services.install() }
                    if statusStore.isDaemonActive { Button("Dienst entfernen…", role: .destructive) { confirmUninstall = true } }
                    if services.isBusy { ProgressView().controlSize(.small) }
                }.disabled(services.isBusy)
                Text("Der Hintergrunddienst benötigt Administratorrechte. Im macOS-Modus überwacht er den Akku, ohne ein eigenes Ladelimit anzuwenden.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = services.message { Text(message).font(.caption).foregroundStyle(services.isError ? Color.orange : Color.secondary) }
                if configStore.hasWriteError {
                    Text("Einstellungen nicht gespeichert: \(configStore.writeErrorMessage ?? "Unbekannter Fehler")")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Erneut speichern") { configStore.saveConfigAtomically() }
                }
            } header: { Text("Hintergrunddienst") }

            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.1")
                Text("Verlauf und Einstellungen bleiben auf diesem Mac. Keine Anmeldung, keine Cloud. Die Akkugesundheit ist eine Schätzung aus den gemeldeten Kapazitäten.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("BatteryGuard beenden") {
                    configStore.flushPendingSave()
                    NSApplication.shared.terminate(nil)
                }
                Text("Der Dienst und geplante Ladeaktionen bleiben nach dem Beenden der App aktiv. Die Verlaufsaufzeichnung endet.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("BatteryGuard") }
        }
        .formStyle(.grouped)
        .confirmationDialog("Hintergrunddienst entfernen?", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("Dienst entfernen", role: .destructive) { services.uninstall() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Ladesteuerung wird zurückgesetzt. macOS übernimmt wieder. Dein lokaler Verlauf bleibt erhalten.")
        }
    }
}
