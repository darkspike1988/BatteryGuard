import SwiftUI
import AppKit
import BatteryGuardShared

struct PopoverContentView: View {
    @Bindable var statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    let historyStore: HistoryStore
    @State private var editingLimits = false
    @Environment(\.openWindow) private var openWindow

    private var chargingAvailable: Bool {
        statusStore.supportsChargingPlans && statusStore.status.state != .unsupported && configStore.config.mode != .native && configStore.config.mode != .direct
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("BatteryGuard", systemImage: "shield.lefthalf.filled").font(.callout.weight(.semibold))
                Spacer()
                Button { openWindow(id: "dashboard"); NSApplication.shared.activate(ignoringOtherApps: true) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Übersicht, Verlauf und Einstellungen öffnen")
                .accessibilityLabel("BatteryGuard öffnen")
            }
            BatteryHeroView(status: statusStore.status, config: configStore.config,
                            active: statusStore.isDaemonActive, compact: true)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Ladeprofil").font(.callout.weight(.medium))
                    Spacer()
                    Text(configStore.config.mode == .native ? "macOS" : "\(configStore.config.upperLimit) % Limit")
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
                    Text("Profil wählen oder Schutz starten, um BatteryGuard zu aktivieren.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    if configStore.config.effective(at: Date()).chargeToFullOnce {
                        configStore.cancelFullCharge()
                        configStore.config.travelReadyAt = nil
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
                       && !configStore.config.isPaused(at: Date()) ? "Schutz pausieren" : "Schutz starten") {
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
        .padding(22).frame(width: 370)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { configStore.flushPendingSave() }
    }
}
