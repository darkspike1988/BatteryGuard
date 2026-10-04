import SwiftUI
import AppKit
import UserNotifications
import BatteryGuardShared

struct PreferencesView: View {
    @Bindable var statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    @Bindable var services: ServiceManager
    var updates: UpdateStore? = nil
    var api: LocalAPIStore? = nil
    @Bindable private var presence = AppPresence.shared
    @Environment(\.openWindow) private var openWindow
    @State private var confirmUninstall = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationAuthorization: UNAuthorizationStatus?
    @State private var notificationAlertsEnabled = false
    @State private var requestingNotifications = false
    @State private var notificationError: String?
    @AppStorage("bg.notifyLow") private var notifyLow = true
    @AppStorage(LowBatteryWarningPolicy.userDefaultsKey) private var lowBatteryThreshold = LowBatteryWarningPolicy.defaultThreshold
    @AppStorage("bg.notifyLimit") private var notifyLimit = false
    @AppStorage("bg.notifyHeat") private var notifyHeat = true
    @AppStorage(MenuBarIconStyle.appStorageKey) private var menuBarIconStyle: MenuBarIconStyle = .ring
    @AppStorage("bg.menuBarDisplay") private var menuBarDisplay: MenuBarDisplayMode = .percent

    @AppStorage("bg.menuShowTemperature") private var menuShowTemperature = false
    @AppStorage("bg.menuShowPower") private var menuShowPower = false
    @AppStorage("bg.menuShowHealth") private var menuShowHealth = false
    @AppStorage("bg.menuShowPowerFlow") private var menuShowPowerFlow = false

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
                            in: 5...min(95, configStore.config.upperLimit - 1))
                    Stepper("Stoppen bei \(configStore.config.upperLimit) %", value: $configStore.config.upperLimit,
                            in: max(20, configStore.config.lowerLimit + 1)...100)
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
                if notifyLow {
                    Stepper(
                        "Warnen bei \(LowBatteryWarningPolicy.clampThreshold(lowBatteryThreshold)) %",
                        value: Binding(
                            get: { LowBatteryWarningPolicy.clampThreshold(lowBatteryThreshold) },
                            set: { lowBatteryThreshold = LowBatteryWarningPolicy.clampThreshold($0) }
                        ),
                        in: LowBatteryWarningPolicy.validRange
                    )
                }
                Text("Die Warnschwelle ist unabhängig von deinem Ladeprofil. Standard: 20 %.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Beim Erreichen des Ladelimits", isOn: $notifyLimit)
                Toggle("Bei hoher Akkutemperatur", isOn: $notifyHeat)
                LabeledContent("macOS-Freigabe", value: notificationPermissionDescription)
                if notificationAuthorization == .notDetermined {
                    Button(requestingNotifications ? "Freigabe wird angefragt …" : "Mitteilungen erlauben") {
                        Task { await requestNotificationPermission() }
                    }.disabled(requestingNotifications)
                }
                if notificationAuthorization == .denied || (notificationAuthorization == .authorized && !notificationAlertsEnabled) {
                    Button("Mitteilungseinstellungen öffnen") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                }
                if let notificationError { Text(notificationError).font(.caption).foregroundStyle(.orange) }
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
                Picker("Symbolstil", selection: $menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Menüleistenanzeige", selection: $menuBarDisplay) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("Wähle das Menüleistensymbol und die Zusatzanzeige. Akku-Leistung ist Lade-/Entladefluss, nicht gesamte Mac-Leistung.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Temperatur im Menüfenster", isOn: $menuShowTemperature)
                Toggle("Akku-Leistung im Menüfenster", isOn: $menuShowPower)
                Toggle("Akkugesundheit im Menüfenster", isOn: $menuShowHealth)
                Toggle("Energiefluss im Menüfenster", isOn: $menuShowPowerFlow)
                Button("Darstellung zurücksetzen") {
                    // AppStorage bindings respect an injected preview store.
                    menuBarIconStyle = .ring
                    menuBarDisplay = .percent
                    menuShowTemperature = false
                    menuShowPower = false
                    menuShowHealth = false
                    menuShowPowerFlow = false
                }
            } header: { Text("Menüleiste") }

            if let api { APISettingsView(api: api) }

            Section {
                LabeledContent("Status", value: statusStore.isDaemonActive ? "Verbunden" : "Nicht erreichbar")
                if let notice = statusStore.status.configurationNotice {
                    Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
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
                    Button("Erneut speichern") { configStore.saveConfig() }
                }
            } header: { Text("Hintergrunddienst") }

            Section {
                LabeledContent("Version", value: AppVersion.installed)
                Text("Verlauf und Einstellungen bleiben auf diesem Mac. Keine Anmeldung, keine Cloud. Die Akkugesundheit ist eine Schätzung aus den gemeldeten Kapazitäten.")
                    .font(.caption).foregroundStyle(.secondary)
                if let updates {
                    Toggle("Automatisch nach Updates suchen", isOn: Binding(
                        get: { updates.automaticChecksEnabled },
                        set: { updates.automaticChecksEnabled = $0 }
                    ))
                    Text("Höchstens täglich über GitHub. Neue Versionen werden in der App angezeigt; bei erlaubten Mitteilungen auch als Hinweis. Downloads starten erst nach deinem Klick.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Updates & Changelog …") {
                    openWindow(id: "updates")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Button("B-Guard beenden") {
                    configStore.flushPendingSave()
                    NSApplication.shared.terminate(nil)
                }
                Text("Der Dienst und geplante Ladeaktionen bleiben nach dem Beenden der App aktiv. Die Verlaufsaufzeichnung endet.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("B-Guard") }
        }
        .formStyle(.grouped)
        .task { await refreshNotificationPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationPermission() } }
        }
        .confirmationDialog("Hintergrunddienst entfernen?", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("Dienst entfernen", role: .destructive) { services.uninstall() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Ladesteuerung wird zurückgesetzt. macOS übernimmt wieder. Dein lokaler Verlauf bleibt erhalten.")
        }
    }

    private var notificationPermissionDescription: String {
        guard Bundle.main.bundleIdentifier != nil else { return "Nur in der installierten App verfügbar" }
        switch notificationAuthorization {
        case .authorized: return notificationAlertsEnabled ? "Erlaubt" : "Erlaubt · Hinweise ausgeschaltet"
        case .denied: return "Nicht erlaubt"
        case .notDetermined: return "Noch nicht angefragt"
        case .provisional: return "Still erlaubt"
        case nil: return "Wird geprüft …"
        @unknown default: return "Unbekannt"
        }
    }

    @MainActor private func refreshNotificationPermission() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = settings.authorizationStatus
        notificationAlertsEnabled = settings.alertSetting == .enabled
    }

    @MainActor private func requestNotificationPermission() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        requestingNotifications = true
        defer { requestingNotifications = false }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationError = nil
        } catch { notificationError = "Freigabe konnte nicht angefragt werden: " + error.localizedDescription }
        await refreshNotificationPermission()
    }
}
