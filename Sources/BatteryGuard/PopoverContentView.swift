import SwiftUI
import AppKit
import BatteryGuardShared

struct PopoverContentView: View {
    @Bindable var statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    let historyStore: HistoryStore
    var updates: UpdateStore? = nil
    @AppStorage("bg.menuShowTemperature") private var showTemperature = false
    @AppStorage("bg.menuShowPower") private var showPower = false
    @AppStorage("bg.menuShowHealth") private var showHealth = false
    @AppStorage("bg.menuShowPowerFlow") private var showPowerFlow = false
    @AppStorage("bg.menuCardOrder") private var cardOrder = MenuCardLayout.defaultRawOrder
    @AppStorage("bg.menuShowHistory") private var showHistory = false
    @AppStorage("bg.menuCardsCompact") private var cardsCompact = false
    @State private var editingLimits = false
    @Environment(\.openWindow) private var openWindow

    private var chargingAvailable: Bool {
        statusStore.supportsChargingPlans && statusStore.status.state != .unsupported && configStore.config.mode != .native && configStore.config.mode != .direct
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: cardsCompact ? 14 : 20) {
            HStack {
                Label("B-Guard", systemImage: "shield.lefthalf.filled").font(.callout.weight(.semibold))
                Spacer()
                Button { openWindow(id: "dashboard"); NSApplication.shared.activate(ignoringOtherApps: true) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Übersicht, Verlauf und Einstellungen öffnen")
                .accessibilityLabel("B-Guard öffnen")
            }
            if let updates, updates.updateAvailable, let release = updates.release {
                Button {
                    openWindow(id: "updates")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("B-Guard \(release.version) verfügbar · Was ist neu?", systemImage: "arrow.down.circle")
                        .font(.callout)
                }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            BatteryHeroView(status: statusStore.status, config: configStore.config,
                            active: statusStore.isDaemonActive, compact: true)
            let orderedCards = MenuCardLayout.validate(rawOrder: cardOrder)
            ForEach(orderedCards) { card in
                renderCard(card)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Ladeprofil").font(.callout.weight(.medium))
                    Spacer()
                    Text(configStore.config.mode == .native || statusStore.status.usesNativeDesktopFallback ? "macOS" : "\(configStore.config.upperLimit) % Limit")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Menu {
                    ForEach(BGProfile.allCases) { profile in
                        Button("\(profile.title) · \(profile.lower)–\(profile.upper) %") {
                            configStore.activateProfile(profile)
                        }
                    }
                    Divider()
                    Button("Eigene Grenzen ändern …") { editingLimits.toggle() }
                } label: {
                    HStack {
                        Text("\(BGProfile.allCases.first(where: { $0.matches(configStore.config) })?.title ?? "Eigene Grenzen") · \(configStore.config.lowerLimit)–\(configStore.config.upperLimit) %")
                        Spacer()
                        Text("\(configStore.config.lowerLimit)–\(configStore.config.upperLimit) %")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!statusStore.supportsChargingPlans)
                if editingLimits {
                    Stepper("Minimum: \(configStore.config.lowerLimit) %",
                            value: $configStore.config.lowerLimit,
                            in: 5...min(95, configStore.config.upperLimit - 1))
                    Stepper("Maximum: \(configStore.config.upperLimit) %",
                            value: $configStore.config.upperLimit,
                            in: max(20, configStore.config.lowerLimit + 1)...100)
                    Text("Eigene Grenzen werden automatisch gespeichert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if configStore.config.mode == .native {
                    Text("Profil wählen oder Schutz starten, um B-Guard zu aktivieren.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    if configStore.config.effective(at: Date()).chargeToFullOnce {
                        configStore.cancelFullCharge()
                    } else { configStore.startFullCharge() }
                } label: {
                    Label(configStore.config.effective(at: Date()).chargeToFullOnce ? "Vollladen beenden" : "Einmal voll laden", systemImage: "bolt")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(!chargingAvailable)
                Menu {
                    if configStore.config.isPaused(at: Date()) {
                        Button("Schutz fortsetzen") { configStore.resumeProtection() }
                    } else {
                        Button("Für 1 Stunde pausieren") { configStore.pause(for: 3600) }
                        Button("Für 2 Stunden pausieren") { configStore.pause(for: 7200) }
                    }
                } label: { Image(systemName: "pause") }
                .menuStyle(.borderlessButton).fixedSize().disabled(!chargingAvailable || !configStore.config.enabled)
                .help("Schutz mit automatischer Wiederaufnahme pausieren")
                .accessibilityLabel("Schutz pausieren")
            }
            HStack {
                Button(configStore.config.enabled && configStore.config.mode != .native
                       && !configStore.config.isPaused(at: Date()) ? "Schutz ausschalten" : "Schutz einschalten") {
                    let running = configStore.config.enabled && configStore.config.mode != .native
                        && !configStore.config.isPaused(at: Date())
                    configStore.setProtectionEnabled(!running)
                }
                .disabled(!statusStore.supportsChargingPlans)
                Spacer()
                Button("Beenden") {
                    configStore.flushPendingSave()
                    NSApplication.shared.terminate(nil)
                }
                .help("App beenden. Der Hintergrunddienst steuert das Laden weiter.")
            }
            .buttonStyle(.bordered)
            Button("Updates & Neuigkeiten …") {
                openWindow(id: "updates")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            if configStore.hasWriteError {
                Label("Einstellungen konnten nicht gespeichert werden.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Circle().fill(statusStore.isDaemonActive ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(statusStore.isDaemonActive ? "Dienst verbunden" : "Dienst nicht erreichbar").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Übersicht") { openWindow(id: "dashboard"); NSApplication.shared.activate(ignoringOtherApps: true) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            }
        }
        .padding(cardsCompact ? 16 : 22)
        }.frame(width: 370).frame(maxHeight: 700)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { configStore.flushPendingSave() }
    }

    @ViewBuilder
    private func renderCard(_ card: MenuCardType) -> some View {
        switch card {
        case .metrics:
            if showTemperature || showPower || showHealth {
                HStack(alignment: .top, spacing: cardsCompact ? 6 : 8) {
                    if showTemperature {
                        menuMetric("Temperatur", value: MenuBarDisplayFormatter.formatTemperature(statusStore.status.temperatureCelsius, isDaemonActive: statusStore.isDaemonActive))
                    }
                    if showPower {
                        menuMetric("Akku-Leistung", value: MenuBarDisplayFormatter.formatPower(statusStore.status.watts, isDaemonActive: statusStore.isDaemonActive))
                            .help("Lade-/Entladefluss, nicht der gesamte Mac-Verbrauch. 0 W ist möglich, wenn das Netzteil den Mac versorgt.")
                    }
                    if showHealth {
                        menuMetric("Gesundheit", value: statusStore.isDaemonActive ? statusStore.status.healthPercent.map { "\($0) %" } ?? "– %" : "– %")
                    }
                }
            }
        case .powerFlow:
            if showPowerFlow {
                PowerFlowView(sample: statusStore.powerFlow, compact: true)
            }
        case .history:
            if showHistory {
                historyCard
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: cardsCompact ? 4 : 8) {
            HStack {
                Label("Verlauf", systemImage: "clock")
                    .font(cardsCompact ? .caption.weight(.medium) : .callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = historyStore.samples.last {
                    Text("Zuletzt " + last.timestamp.formatted(date: Calendar.current.isDateInToday(last.timestamp) ? .omitted : .abbreviated, time: .shortened))
                        .font(cardsCompact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let last = historyStore.samples.last {
                HStack(alignment: .top, spacing: cardsCompact ? 6 : 8) {
                    menuMetric("Letzter Stand", value: "\(last.percent) %")
                    if let watts = last.watts {
                        menuMetric("Akku-Leistung", value: MenuBarDisplayFormatter.formatPower(watts, isDaemonActive: true))
                    }
                    if let temp = last.temperature {
                        menuMetric("Temperatur", value: MenuBarDisplayFormatter.formatTemperature(temp, isDaemonActive: true))
                    }
                }
            } else {
                Text("Keine Verlaufsdaten verfügbar")
                    .font(cardsCompact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func menuMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: cardsCompact ? 2 : 5) {
            Text(title).font(cardsCompact ? .caption2 : .caption).foregroundStyle(.secondary)
            Text(value).font((cardsCompact ? Font.subheadline : Font.callout).weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

}
