import SwiftUI
import BatteryGuardShared

private enum DashboardPage: String, CaseIterable, Identifiable {
    case overview = "Übersicht", history = "Verlauf", settings = "Einstellungen"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: "square.grid.2x2"; case .history: "chart.xyaxis.line"; case .settings: "slider.horizontal.3" }
    }
}

struct DashboardView: View {
    @Bindable var statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    let historyStore: HistoryStore
    let services: ServiceManager
    var updates: UpdateStore? = nil
    var api: LocalAPIStore? = nil
    @Environment(\.openWindow) private var openWindow
    @State private var page: DashboardPage? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 32, weight: .light)).foregroundStyle(Color.accentColor)
                    Text("B-Guard").font(.headline)
                    Text("Energie. Bewusst.").font(.caption).foregroundStyle(.secondary)
                }.padding(22).padding(.top, 10)
                List(DashboardPage.allCases, selection: $page) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).foregroundStyle(Color.secondary).frame(width: 18)
                        Text(item.rawValue).foregroundStyle(Color.primary)
                    }.tag(item)
                }.listStyle(.sidebar)
                HStack(spacing: 7) {
                    Circle().fill(statusStore.isDaemonActive ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(statusStore.isDaemonActive ? "Dienst verbunden" : "Dienst nicht erreichbar").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch page ?? .overview {
                case .overview:
                    OverviewView(statusStore: statusStore, configStore: configStore, history: historyStore, updates: updates)
                case .history:
                    HistoryView(history: historyStore, currentConfig: configStore.config)
                case .settings:
                    PreferencesView(statusStore: statusStore, configStore: configStore, services: services, updates: updates, api: api)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(page?.rawValue ?? "B-Guard")
        }
        .frame(minWidth: 780, minHeight: 600)
        .onDisappear { configStore.flushPendingSave() }
    }
}

struct OverviewView: View {
    let statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    let history: HistoryStore
    var updates: UpdateStore? = nil
    @Environment(\.openWindow) private var openWindow
    @State private var readyAt = Date().addingTimeInterval(12 * 3600)
    private var canControl: Bool {
        statusStore.supportsChargingPlans && statusStore.status.state != .unsupported && configStore.config.mode != .native && configStore.config.mode != .direct
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BGSectionHeading(title: "Ein guter Platz für deinen Akku.", subtitle: "Lade bewusst. Bleib flexibel. Behalte den Überblick.")
                BGPanel {
                    HStack(alignment: .center, spacing: 24) {
                        BatteryHeroView(status: statusStore.status, config: configStore.config, active: statusStore.isDaemonActive)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 9) {
                            Text(statusStore.isDaemonActive && statusStore.status.usesNativeDesktopFallback ? "MACOS-LIMIT" : "LADEZIEL").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                            Text(configStore.config.mode == .native || (statusStore.isDaemonActive && statusStore.status.usesNativeDesktopFallback) ? statusStore.status.nativeChargeLimit.map { "\($0) %" } ?? "macOS" : "\(configStore.config.upperLimit) %")
                                .font(.system(size: 28, weight: .light)).monospacedDigit()
                            Text(statusStore.isDaemonActive && statusStore.status.usesNativeDesktopFallback ? "Profilziel: \(configStore.config.upperLimit) %" : profileName).font(.caption).foregroundStyle(.secondary)
                        }.frame(minWidth: 86)
                    }
                }
                if let updates, updates.updateAvailable, let release = updates.release {
                    BGPanel {
                        HStack {
                            Label("B-Guard \(release.version) ist verfügbar.", systemImage: "arrow.down.circle")
                            Spacer()
                            Button("Änderungen ansehen") { openWindow(id: "updates") }
                        }.font(.callout)
                    }
                }
                if statusStore.daemonNeedsUpdate {
                    BGPanel {
                        Label("Aktualisiere den Hintergrunddienst in den Einstellungen, damit die aktuellen Funktionen und Fehlerkorrekturen aktiv sind.", systemImage: "arrow.down.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if statusStore.isDaemonActive, let notice = statusStore.status.configurationNotice {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    metric("Temperatur", value: statusStore.status.temperatureCelsius.map { String(format: "%.1f °C", $0) }, symbol: "thermometer.medium")
                    metric("Gesundheit", value: statusStore.status.healthPercent.map { "\($0) %" }, symbol: "heart")
                    metric("Akku-Leistung", value: MenuBarDisplayFormatter.formatPower(statusStore.status.watts, isDaemonActive: statusStore.isDaemonActive), symbol: "bolt")
                        .help("Lade-/Entladefluss des Akkus. Der gesamte Mac-Verbrauch ist ein anderer Messwert.")
                }
                Text(batteryPowerExplanation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                BGPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Dein Ladeprofil").font(.headline)
                            Spacer()
                            Text(profileName).font(.caption).foregroundStyle(.secondary)
                        }
                        ProfilePickerView(store: configStore)
                        Text(configStore.config.mode == .native
                             ? "Im macOS-Modus bleibt B-Guard ein Beobachter. Die Steuerung kannst du in den Einstellungen aktivieren."
                             : "Ein Profil ändert nur deinen Ladebereich. Hitzeschutz und weitere Einstellungen bleiben erhalten.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let nativeLimit = statusStore.status.nativeChargeLimit,
                   nativeLimit < (configStore.config.effective(at: Date()).chargeToFullOnce ? 100 : configStore.config.upperLimit),
                   configStore.config.mode != .native {
                    BGPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("macOS begrenzt zusätzlich auf \(nativeLimit) %", systemImage: "info.circle").font(.callout.weight(.medium))
                            Text("Für ein höheres Ziel oder Vollladen musst du das native Limit in den Batterieeinstellungen anheben. B-Guard verändert diese Systemeinstellung nicht.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Batterieeinstellungen öffnen") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
                            }.font(.caption)
                        }
                    }
                }
                ChargingActionsView(configStore: configStore, canControl: canControl)
                travelPanel
                if statusStore.isDaemonActive {
                    Label(insight, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 3)
                }
            }.padding(28).frame(maxWidth: 880)
        }
    }

    private var profileName: String {
        if configStore.config.mode == .native { return "Nur beobachten" }
        return BGProfile.allCases.first { $0.matches(configStore.config) }?.title ?? "Eigener Ladebereich"
    }

    private var insight: String {
        if statusStore.status.usesNativeDesktopFallback {
            return "Bei externem Monitor oder geschlossenem Deckel bleibt das Netzteil verbunden. macOS steuert das Laden; das B-Guard-Profilziel wird dabei nicht erzwungen."
        }
        if let t = statusStore.status.temperatureCelsius, t >= 40 {
            return "Der Akku ist warm. Prüfe Hitzeschutz und Belüftung, bevor du länger lädst."
        }
        if configStore.config.mode == .pendulum || (!statusStore.status.smcKeysDetected.contains("CHTE") && !statusStore.status.smcKeysDetected.contains("CH0B") && configStore.config.mode == .auto) {
            return "Dieser Mac nutzt zum Regeln den Netzteil-Schalter. Dabei läuft er zwischen Ladelimit und fünf Prozentpunkten darunter vom Akku."
        }
        return "Dein Verlauf bleibt auf diesem Mac. B-Guard zeichnet nur auf, während die App läuft und aktuelle Messwerte verfügbar sind."
    }

    private func metric(_ title: String, value: String?, symbol: String) -> some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
                Text(statusStore.isDaemonActive ? (value ?? "—") : "—")
                    .font(.system(size: 22, weight: .medium)).monospacedDigit()
                if title == "Akkuleistung" {
                    Text(!statusStore.isDaemonActive || value == nil ? "Messwert nicht verfügbar" : "Plus: Laden · Minus: Entladen")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var batteryPowerExplanation: String {
        guard statusStore.isDaemonActive, let watts = statusStore.status.watts, watts.isFinite else {
            return "Akku-Leistung: Messwert nicht verfügbar."
        }
        if abs(watts) < 0.05 {
            return statusStore.status.pluggedIn
                ? "Kein messbarer Akkustrom. Das Netzteil kann den Mac versorgen, ohne den Akku zu laden. 0 W bedeutet nicht, dass der Mac keinen Strom verbraucht."
                : "Momentan kein messbarer Akkustrom. Angezeigt wird der Lade-/Entladefluss, nicht der gesamte Mac-Verbrauch."
        }
        return watts > 0
            ? "Akku-Leistung: Energie fließt in den Akku. Der gesamte Mac-Verbrauch wird hier nicht gemessen."
            : "Akku-Leistung: Energie fließt aus dem Akku. Der gesamte Mac-Verbrauch wird hier nicht gemessen."
    }

    private var travelPanel: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Bereit für unterwegs", systemImage: "suitcase.rolling").font(.headline)
                    Spacer()
                    if configStore.config.travelReadyAt != nil {
                        Button("Plan entfernen") { configStore.config.travelReadyAt = nil }.font(.caption)
                    }
                }
                if let planned = configStore.config.travelReadyAt,
                   planned.addingTimeInterval(BGConfig.travelGraceTime) > Date() {
                    Text("Geplant für \(planned.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout.weight(.medium))
                    Text(configStore.config.mode == .native
                         ? "Der Plan wartet, solange macOS die Ladung steuert. Aktiviere die B-Guard-Steuerung in den Einstellungen, damit er ausgeführt wird."
                         : "Vollladen startet drei Stunden vorher. Nach 100 % oder spätestens eine Stunde nach dem Termin gilt wieder dein Ladeprofil.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Plane eine volle Ladung vor deiner nächsten Reise.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        DatePicker("Abfahrt", selection: $readyAt, in: Date()...Date().addingTimeInterval(7 * 24 * 3600), displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.field)
                        Spacer()
                        Button("Planen") { configStore.scheduleTravel(readyAt: readyAt) }.buttonStyle(.borderedProminent)
                            .disabled(!canControl || readyAt <= Date())
                    }
                    Text("Der Mac muss am Netzteil und wach sein. Hitzeschutz bleibt aktiv. Eine volle Ladung zum Termin kann nicht garantiert werden.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ChargingActionsView: View {
    @Bindable var configStore: ConfigStore
    let canControl: Bool
    private var fullActive: Bool { configStore.config.effective(at: Date()).chargeToFullOnce }

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Flexibel laden").font(.headline)
                HStack(spacing: 12) {
                    Button {
                        if fullActive {
                            configStore.cancelFullCharge()
                        } else { configStore.startFullCharge() }
                    } label: {
                        Label(fullActive ? "Vollladen beenden" : "Jetzt auf 100 % laden", systemImage: "bolt")
                    }.buttonStyle(.bordered).disabled(!canControl)
                    if configStore.config.isPaused(at: Date()) {
                        Button("Schutz fortsetzen") { configStore.resumeProtection() }.buttonStyle(.bordered).disabled(!canControl)
                    } else {
                        Menu("Schutz pausieren") {
                            Button("1 Stunde") { configStore.pause(for: 3600) }
                            Button("2 Stunden") { configStore.pause(for: 7200) }
                            Button("Bis morgen (12 Stunden)") { configStore.pause(for: 12 * 3600) }
                        }.menuStyle(.borderlessButton).fixedSize().disabled(!canControl || !configStore.config.enabled)
                    }
                    Spacer(minLength: 0)
                }
                Text(exceptionDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exceptionDescription: String {
        if let pause = configStore.config.pauseUntil, pause > Date() {
            return "Automatisch wieder aktiv: \(pause.formatted(date: .omitted, time: .shortened)). Während der Pause greift B-Guard nicht ein."
        }
        if fullActive { return "Nach 100 % kehrt B-Guard zum Ladeprofil zurück. Manuelles Vollladen endet spätestens nach acht Stunden." }
        return "Vollladen behält den Hitzeschutz bei. Eine Pause setzt die B-Guard-Steuerung für die gewählte Dauer aus."
    }
}
