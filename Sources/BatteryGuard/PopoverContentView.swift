import SwiftUI
import AppKit
import BatteryGuardShared

struct PopoverContentView: View {
    @Bindable var statusStore: StatusStore
    @Bindable var configStore: ConfigStore
    
    @State private var settingsExpanded = false
    private var appPresence = AppPresence.shared
    
    init(statusStore: StatusStore, configStore: ConfigStore) {
        self.statusStore = statusStore
        self.configStore = configStore
    }
    
    private var visualState: BGVisualState {
        BGVisualState.resolve(
            status: statusStore.status,
            isDaemonActive: statusStore.isDaemonActive,
            config: configStore.config
        )
    }
    
    public var body: some View {
        ZStack {
            // Transluzenter dynamischer Hintergrund mit langsam schwebenden Farbkugeln
            LiquidGlassBackgroundView(
                accentColor: visualState.accentColor,
                secondaryColor: visualState.secondaryColor
            )
            
            ScrollView(.vertical, showsIndicators: false) {
                // Liquid Glass Effect Container für zusammenhängende Glas-Karten
                GlassContainer(spacing: 10) {
                    // 1. Kopfbereich: Großer Akku-Ladering + Prozent in SF Rounded + Mechanismus-Pille
                    BatteryHeaderCardView(
                        status: statusStore.status,
                        config: configStore.config,
                        isDaemonActive: statusStore.isDaemonActive,
                        visualState: visualState
                    )
                    
                    // 2. 4 Glas-Kacheln für Temperatur, Zyklen, Gesundheit, Leistung
                    StatusTilesGridView(status: statusStore.status)
                    
                    // 3. Neuer Abschnitt 'Modus': Segment (Glas-Picker) mit Auto, Nativ, Pendel
                    ModePickerView(mode: $configStore.config.mode)
                    
                    // 4. Custom Range-Slider als Glas-Kapsel mit Presets
                    BatteryRangeSlider(
                        lowerLimit: $configStore.config.lowerLimit,
                        upperLimit: $configStore.config.upperLimit,
                        isEnabled: $configStore.config.enabled,
                        currentPercent: statusStore.status.percent
                    )
                    
                    // 5. Toggles in Glas-Zeilen
                    togglesView
                    
                    // 5b. Einstellungen Dropdown
                    settingsView
                    
                    // 6. Schreibfehler-Banner falls vorhanden
                    if configStore.hasWriteError {
                        writeErrorBanner
                    }
                    
                    // 7. Fußzeile: Daemon-Status + Beenden + Open Source
                    footerView
                }
                .padding(14)
            }
        }
        .frame(width: 340, height: 620)
    }
    
    // MARK: - Toggles in Glas-Zeilen
    
    private var togglesView: some View {
        VStack(spacing: 7) {
            // Zeile 1: Schutz aktiv
            HStack(spacing: 10) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(configStore.config.enabled ? visualState.accentColor : Color.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Schutz aktiv")
                        .font(.callout.weight(.medium))
                    Text("Ladelimitierung am Netzteil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $configStore.config.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .adaptiveGlassCard(cornerRadius: 12)
            .help("Aktiviert oder deaktiviert den BatteryGuard-Ladeschutz komplett. Im deaktivierten Zustand verhält sich dein Mac so, als wäre BatteryGuard nicht installiert, und lädt den Akku immer bis 100%.")
            
            // Zeile 2: Am Netzteil aktiv entladen
            HStack(spacing: 10) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(configStore.config.activeDischargeAboveUpper ? Color.orange : Color.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Am Netzteil aktiv entladen")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("Trennt Adapter bei Akku > Maximum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $configStore.config.activeDischargeAboveUpper)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!configStore.config.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .adaptiveGlassCard(cornerRadius: 12)
            .help("Wenn der Akku voller ist als das erlaubte Maximum (z.B. nach dem Abstecken und wieder Anstecken), wird das Netzteil virtuell deaktiviert, um den Akku auf das Zielniveau zu entladen.")
            
            // Zeile 3: Hitzeschutz (35–45 °C)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(configStore.config.heatProtectionCelsius > 0 ? Color.orange : Color.secondary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hitzeschutz")
                            .font(.callout.weight(.medium))
                        Text("Laden pausieren bei Überhitzung")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { configStore.config.heatProtectionCelsius > 0 },
                        set: { isEnabled in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                configStore.config.heatProtectionCelsius = isEnabled ? 40 : 0
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!configStore.config.enabled)
                }
                
                if configStore.config.heatProtectionCelsius > 0 {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { Double(configStore.config.heatProtectionCelsius) },
                                set: { configStore.config.heatProtectionCelsius = Int($0) }
                            ),
                            in: 35...45,
                            step: 1
                        )
                        
                        Text("\(configStore.config.heatProtectionCelsius) °C")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(width: 44, alignment: .trailing)
                        
                        Stepper(
                            "",
                            value: $configStore.config.heatProtectionCelsius,
                            in: 35...45
                        )
                        .labelsHidden()
                    }
                    .padding(.top, 2)
                    .padding(.leading, 30)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .adaptiveGlassCard(cornerRadius: 12)
            .help("Pausiert den Ladevorgang (und trennt bei Bedarf virtuell das Netzteil), wenn der Akku heißer als die eingestellte Temperatur wird, um Zellverschleiß zu verhindern.")
            
            // Zeile 4: Einmal voll laden
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    configStore.config.chargeToFullOnce.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: configStore.config.chargeToFullOnce ? "bolt.badge.checkmark.fill" : "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(configStore.config.chargeToFullOnce ? Color.green : visualState.accentColor)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Einmal voll laden")
                            .font(.callout.weight(.medium))
                        Text("Bis 100 % vor Reisen")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if configStore.config.chargeToFullOnce {
                        Text("Aktiv")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .adaptiveGlassCapsule(tint: Color.green.opacity(0.18))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .adaptiveGlassCard(cornerRadius: 12)
            .disabled(!configStore.config.enabled)
            .help("Deaktiviert temporär das Ladelimit und lädt den Akku einmalig auf 100% auf. Praktisch, wenn du z. B. vor einer längeren Reise die volle Laufzeit benötigst. Sobald 100% erreicht sind, wird der normale Ladeschutz wieder aktiviert.")
        }
    }
    
    // MARK: - Einstellungen
    private var settingsView: some View {
        DisclosureGroup(isExpanded: $settingsExpanded) {
            VStack(spacing: 8) {
                Divider().opacity(0.5).padding(.vertical, 4)
                
                Toggle(isOn: $configStore.config.magsafeLed) {
                    HStack {
                        Text("MagSafe-LED anpassen")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                @Bindable var presence = appPresence
                
                Toggle(isOn: $presence.launchAtLogin) {
                    HStack {
                        Text("Autostart (Login)")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                Toggle(isOn: $presence.showInDock) {
                    HStack {
                        Text("Im Dock anzeigen")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
                Text("Einstellungen")
                    .font(.callout.weight(.medium))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 12)
    }
    
    // MARK: - Banner & Fußzeile
    
    private var writeErrorBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text("Konfigurationsordner nicht beschreibbar")
                    .font(.caption.weight(.semibold))
                Text("Verzeichnis /Library/Application Support/BatteryGuard fehlt oder ist schreibgeschützt. Bitte Hintergrunddienst installieren.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .adaptiveGlassCard(cornerRadius: 12, tint: Color.orange.opacity(0.12))
    }
    
    private var footerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusStore.isDaemonActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (statusStore.isDaemonActive ? Color.green : Color.red).opacity(0.4), radius: 2)
                
                Text(statusStore.isDaemonActive ? "Dienst aktiv (v\(statusStore.status.daemonVersion))" : "Hintergrunddienst nicht aktiv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !statusStore.isDaemonActive {
                    Button("Dienst installieren…") {
                        installDaemon()
                    }
                    .font(.caption.weight(.medium))
                    .adaptiveGlassProminentButton()
                    .controlSize(.small)
                }
            }
            
            HStack {
                if let url = URL(string: "https://github.com/<user>/BatteryGuard") {
                    Link("Open Source", destination: url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Beenden") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 12)
    }
    
    // MARK: - Daemon Installation
    
    @MainActor
    private func installDaemon() {
        var candidates: [String] = []
        
        // 1. App-Bundle Ressourcen
        if let bundleResource = Bundle.main.path(forResource: "install-daemon", ofType: "sh") {
            candidates.append(bundleResource)
        }
        let bundleResourcePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/install-daemon.sh").path
        candidates.append(bundleResourcePath)
        
        // 2. Relativ zur Executable
        if let execURL = Bundle.main.executableURL {
            candidates.append(execURL.deletingLastPathComponent().appendingPathComponent("../scripts/install-daemon.sh").standardized.path)
            candidates.append(execURL.deletingLastPathComponent().appendingPathComponent("../../scripts/install-daemon.sh").standardized.path)
            candidates.append(execURL.deletingLastPathComponent().appendingPathComponent("../../../scripts/install-daemon.sh").standardized.path)
        }
        
        // 3. Aktuelles Arbeitsverzeichnis / Projekt-Struktur
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("scripts/install-daemon.sh").standardized.path)
        candidates.append(cwd.appendingPathComponent("../scripts/install-daemon.sh").standardized.path)
        candidates.append("/Users/michaelkatschko/BatteryGuard/scripts/install-daemon.sh")
        
        guard let scriptPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            let alert = NSAlert()
            alert.messageText = "Installationsskript nicht gefunden"
            alert.informativeText = "Das Skript 'install-daemon.sh' wurde weder im App-Bundle noch unter scripts/ gefunden."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        Task.detached {
            let escaped = scriptPath.replacingOccurrences(of: "\"", with: "\\\"")
            let scriptSource = "do shell script \"/bin/bash \\\"\(escaped)\\\"\" with administrator privileges"
            
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: scriptSource) {
                _ = appleScript.executeAndReturnError(&errorDict)
                if let errorDict {
                    let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? "Unbekannter Fehler bei der Ausführung."
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Installation fehlgeschlagen"
                        alert.informativeText = errorMsg
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                } else {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Installation erfolgreich"
                        alert.informativeText = "Der Hintergrunddienst wurde erfolgreich installiert."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            }
        }
    }
}
