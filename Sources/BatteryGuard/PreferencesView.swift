import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers
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
    @State private var diagnosticsError: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationAuthorization: UNAuthorizationStatus?
    @State private var notificationAlertsEnabled = false
    @State private var requestingNotifications = false
    @State private var notificationError: String?
    @AppStorage("bg.notifyLow") private var notifyLow = true
    @AppStorage(LowBatteryWarningPolicy.userDefaultsKey) private var lowBatteryThreshold = LowBatteryWarningPolicy.defaultThreshold
    @AppStorage("bg.notifyLimit") private var notifyLimit = false
    @AppStorage("bg.notifyHeat") private var notifyHeat = true
    @AppStorage("bg.notifyCalibration") private var notifyCalibration = true
    @AppStorage("bg.notifyWeekly") private var notifyWeekly = false
    @AppStorage("bg.notifyHealth") private var notifyHealth = true
    @AppStorage("bg.healthThreshold") private var healthThreshold = 80
    @AppStorage(MenuBarIconStyle.appStorageKey) private var menuBarIconStyle: MenuBarIconStyle = .ring
    @AppStorage("bg.menuBarDisplay") private var menuBarDisplay: MenuBarDisplayMode = .percent

    @AppStorage("bg.menuShowTemperature") private var menuShowTemperature = false
    @AppStorage("bg.menuShowPower") private var menuShowPower = false
    @AppStorage("bg.menuShowHealth") private var menuShowHealth = false
    @AppStorage("bg.menuShowPowerFlow") private var menuShowPowerFlow = false
    @AppStorage("bg.menuCardOrder") private var menuCardOrder = MenuCardLayout.defaultRawOrder
    @AppStorage("bg.menuShowNextTask") private var menuShowNextTask = false
    @AppStorage("bg.menuShowHistory") private var menuShowHistory = false
    @AppStorage("bg.menuCardsCompact") private var menuCardsCompact = false

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "B-Guard-Diagnose.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let report = DiagnosticsExport.build(config: configStore.config, status: statusStore.status,
                daemonActive: statusStore.isDaemonActive, apiEnabled: api?.enabled ?? false,
                controlAllowed: api?.allowsControl ?? false)
            try DiagnosticsExport.write(report, to: url)
            diagnosticsError = nil
        } catch { diagnosticsError = error.localizedDescription }
    }

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
                Text(configStore.config.mode.localizedDescription).font(.caption).foregroundStyle(.secondary)
                if configStore.config.mode == .native {
                    Button("macOS-Batterieeinstellungen öffnen") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
                    }
                } else {
                    Toggle("Ladeschutz aktiv", isOn: $configStore.config.enabled)
                    Stepper(L("Laden ab %lld %%", configStore.config.lowerLimit), value: $configStore.config.lowerLimit,
                            in: 5...min(95, configStore.config.upperLimit - 1))
                    Stepper(L("Stoppen bei %lld %%", configStore.config.upperLimit), value: $configStore.config.upperLimit,
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
                Toggle("Bei externem Monitor das Monitorprofil anwenden", isOn: $configStore.config.desktopProfileEnabled)
                if configStore.config.desktopProfileEnabled {
                    Picker("Monitorprofil", selection: Binding(
                        get: { configStore.config.desktopProfile ?? .desk },
                        set: { configStore.config.desktopProfile = $0 }
                    )) {
                        ForEach(BGProfile.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    Text("Ändert nur die Ladegrenzen, solange ein externer Monitor verbunden ist. Pause, Reise- und Sonderpläne bleiben vorrangig; dein gespeichertes Profil wird nicht überschrieben.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Low Power Mode auf Akkubetrieb automatisch aktivieren", isOn: $configStore.config.lowPowerModeOnBattery)
                Text("Nutzt die öffentliche macOS-Einstellung über pmset: an bei Akkubetrieb, aus am Netzteil. B-Guard schreibt dafür keine privaten SMC-Schlüssel.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Systemschlaf beim aktiven Entladen bis zu 30 Minuten verhindern", isOn: $configStore.config.preventSleepWhileDischarging)
                Text("Gilt nur, solange B-Guard den Adapter selbst getrennt hat. Bewusster Schlaf und Deckelschließen bleiben möglich; die Sperre endet spätestens nach 30 Minuten.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Automatik") }

            Section {
                SavedProfilesView(configStore: configStore)
            } header: { Text("Eigene Profile") }

            Section {
                ScheduledTasksView(configStore: configStore)
            } header: { Text("Zeitpläne") }

            Section {
                SpecialChargeActionsView(configStore: configStore, statusStore: statusStore)
                if let deadline = configStore.config.awakeUntilLimitUntil, deadline > Date() {
                    Text(L("Wachhalten angefordert bis spätestens %@", deadline.formatted(date: .omitted, time: .shortened))).font(.caption)
                    Button("Wachhalten beenden") { configStore.performAction(.init(action: .cancelStayAwake)) }
                } else {
                    Button("Bis zum Ladelimit wachhalten · höchstens 2 Stunden") { configStore.performAction(.init(action: .stayAwakeUntilLimit, minutes: 120)) }
                        .disabled(!statusStore.supportsChargingPlans || !statusStore.status.smcKeysDetected.contains(where: { $0 == "CHTE" || $0 == "CH0B" }))
                }
                Text("Verhindert nur automatischen Ruhezustand am Netzteil. Display und bewusst ausgelöster Schlaf bleiben möglich. Bei Abstecken, fehlenden Sensoren, erreichtem Ziel, Frist oder Fehler wird Wachhalten gelöst.").font(.caption).foregroundStyle(.secondary)
                Text("Kalibrierung: 100 % laden → bis 10 % entladen → erneut 100 % laden → eine Stunde halten. Der Assistent bleibt bis zur physischen Hardware-Abnahme gesperrt. Er kann die Ladestandsschätzung verbessern; eine längere Akkulebensdauer wird nicht zugesagt.").font(.caption).foregroundStyle(.secondary)
                if configStore.config.calibrationPlan != nil {
                    Button("Kalibrierung abbrechen") {
                        do { _ = try configStore.performAPIAction(.init(action: .cancelCalibration)) }
                        catch { diagnosticsError = error.localizedDescription }
                    }
                }
            } header: { Text("Sonderaktionen") }

            Section {
                Button("Diagnose exportieren …") { exportDiagnostics() }
                Text("Enthält nur technische Zustände und Fähigkeiten. Keine Tokens, Seriennummern, Profilnamen, persönlichen Pfade oder Reisezeiten.").font(.caption).foregroundStyle(.secondary)
                if let diagnosticsError { Text(diagnosticsError).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Diagnose") }

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
                Toggle("Wartungshinweis bei niedriger Akkukapazität", isOn: $notifyHealth)
                    .help("Meldet höchstens alle 30 Tage, wenn die geschätzte Kapazität unter die Grenze fällt. Das ist kein Hardwaretest.")
                if notifyHealth {
                    Stepper(
                        L("Hinweis unter %lld %%", BatteryHealthAlertPolicy.clampThreshold(healthThreshold)),
                        value: Binding(
                            get: { BatteryHealthAlertPolicy.clampThreshold(healthThreshold) },
                            set: { healthThreshold = BatteryHealthAlertPolicy.clampThreshold($0) }
                        ),
                        in: BatteryHealthAlertPolicy.validRange,
                        step: 5
                    )
                }
                Text("Die geschätzte Kapazität stammt aus Design- und Maximalkapazität. Ein Wert unter der Grenze kann auf einen notwendigen Akkutausch oder eine Wartung hindeuten, ist aber keine Diagnose. Unternehmen können den Wert zusätzlich über die lokale API auslesen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Sechs Wochen ohne Vollladung", isOn: $notifyCalibration)
                    .help("Erinnert höchstens alle zwei Wochen. Eine gelegentliche Vollladung kann die Ladestandsschätzung unterstützen; sie ist kein Gesundheitstest und wird nicht automatisch gestartet.")
                Toggle("Wochenbericht", isOn: $notifyWeekly)
                    .help("Ein lokaler Hinweis pro Woche mit aufgezeichneter Zeit, Ladung über 90 % und Temperatur über 40 °C. Es werden keine Daten gesendet.")
                LabeledContent("macOS-Freigabe", value: notificationPermissionDescription)
                if notificationAuthorization == .notDetermined {
                    Button(L(requestingNotifications ? "Freigabe wird angefragt …" : "Mitteilungen erlauben")) {
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
                        Text(style.localizedTitle).tag(style)
                    }
                }
                Picker("Menüleistenanzeige", selection: $menuBarDisplay) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                Text("Wähle das Menüleistensymbol und die Zusatzanzeige. Akku-Leistung ist Lade-/Entladefluss, nicht gesamte Mac-Leistung.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Temperatur im Menüfenster", isOn: $menuShowTemperature)
                Toggle("Akku-Leistung im Menüfenster", isOn: $menuShowPower)
                Toggle("Akkugesundheit im Menüfenster", isOn: $menuShowHealth)
                Toggle("Energiefluss im Menüfenster", isOn: $menuShowPowerFlow)
                Toggle("Verlauf im Menüfenster", isOn: $menuShowHistory)
                Toggle("Nächste Aufgabe im Menüfenster", isOn: $menuShowNextTask)
                Toggle("Kompakte Kartendarstellung", isOn: $menuCardsCompact)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Karten-Reihenfolge").font(.subheadline.weight(.medium))
                    let cards = MenuCardLayout.validate(rawOrder: menuCardOrder)
                    ForEach(Array(cards.enumerated()), id: \.element) { _, card in
                        HStack {
                            Text(card.localizedTitle)
                            Spacer()
                            Button {
                                menuCardOrder = MenuCardLayout.moveUp(card: card, in: menuCardOrder)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!MenuCardLayout.canMoveUp(card: card, in: cards))
                            .accessibilityLabel(L("%@ nach oben verschieben", card.localizedTitle))

                            Button {
                                menuCardOrder = MenuCardLayout.moveDown(card: card, in: menuCardOrder)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!MenuCardLayout.canMoveDown(card: card, in: cards))
                            .accessibilityLabel(L("%@ nach unten verschieben", card.localizedTitle))
                        }
                    }
                }
                .padding(.vertical, 4)

                Button("Darstellung zurücksetzen") {
                    // AppStorage bindings respect an injected preview store.
                    menuBarIconStyle = .ring
                    menuBarDisplay = .percent
                    menuShowTemperature = false
                    menuShowPower = false
                    menuShowHealth = false
                    menuShowPowerFlow = false
                    menuCardOrder = MenuCardLayout.defaultRawOrder
                    menuShowHistory = false
                    menuShowNextTask = false
                    menuCardsCompact = false
                }
            } header: { Text("Menüleiste") }

            if let api { APISettingsView(api: api) }

            Section {
                LabeledContent("Status", value: L(statusStore.isDaemonActive ? "Verbunden" : "Nicht erreichbar"))
                if let notice = statusStore.status.configurationNotice {
                    Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Dienstversion", value: statusStore.isDaemonActive ? statusStore.status.daemonVersion : "—")
                if statusStore.isDaemonActive {
                    LabeledContent("Ladezyklen", value: statusStore.status.cycleCount.map(String.init) ?? "—")
                    LabeledContent("SMC-Unterstützung", value: statusStore.status.smcKeysDetected.joined(separator: ", "))
                }
                HStack {
                    Button(L(statusStore.isDaemonActive ? "Dienst aktualisieren" : "Dienst installieren")) { services.install() }
                    if statusStore.isDaemonActive { Button("Dienst entfernen…", role: .destructive) { confirmUninstall = true } }
                    if services.isBusy { ProgressView().controlSize(.small) }
                }.disabled(services.isBusy)
                Text("Der Hintergrunddienst benötigt Administratorrechte. Im macOS-Modus überwacht er den Akku, ohne ein eigenes Ladelimit anzuwenden.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = services.message { Text(message).font(.caption).foregroundStyle(services.isError ? Color.orange : Color.secondary) }
                if configStore.hasWriteError {
                    Text(L("Einstellungen nicht gespeichert: %@", configStore.writeErrorMessage ?? L("Unbekannter Fehler")))
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
        guard Bundle.main.bundleIdentifier != nil else { return L("Nur in der installierten App verfügbar") }
        switch notificationAuthorization {
        case .authorized: return L(notificationAlertsEnabled ? "Erlaubt" : "Erlaubt · Hinweise ausgeschaltet")
        case .denied: return L("Nicht erlaubt")
        case .notDetermined: return L("Noch nicht angefragt")
        case .provisional: return L("Still erlaubt")
        case nil: return L("Wird geprüft …")
        @unknown default: return L("Unbekannt")
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
        } catch { notificationError = L("Freigabe konnte nicht angefragt werden: %@", error.localizedDescription) }
        await refreshNotificationPermission()
    }
}
