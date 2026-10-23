import SwiftUI
import AppKit
import BatteryGuardShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var configStore: ConfigStore?
    @MainActor static weak var updateStore: UpdateStore?
    @MainActor static weak var apiStore: LocalAPIStore?
    private var setupWindow: NSWindow?
    /// Erneutes Öffnen aus Programme oder Dock blendet ein verborgenes Menüleistensymbol wieder ein.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: "bg.showMenuBarIcon")
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.configStore?.flushPendingSave()
        Self.updateStore?.stopAutomaticChecks()
        Self.apiStore?.stop()
        return .terminateNow
    }
    /// `bguard://`-Adressen aus Kurzbefehlen, Skripten oder anderen Apps.
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.handle(urls)
    }

    @MainActor static func handle(_ urls: [URL]) {
        for url in urls {
            do {
                _ = try BatteryWriteIntentExecution.perform(try BGURLCommand.request(for: url))
                configStore?.loadConfig()
            } catch {
                NotificationManager.shared.notify(title: "B-Guard", body: L("Befehl nicht ausgeführt: %@", error.localizedDescription))
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DesignPreview.isRendering { DesignPreview.render(); return }
        let arguments = ProcessInfo.processInfo.arguments
        // Kommandozeile: BatteryGuard --run "bguard://limit/60"
        if let index = arguments.firstIndex(of: "--run"), arguments.count > index + 1 {
            do {
                guard let url = URL(string: arguments[index + 1]) else { throw BGURLCommand.ParseError.unsupported("Unbekannte Adresse.") }
                let saved = try BatteryWriteIntentExecution.perform(try BGURLCommand.request(for: url))
                print(String(decoding: try BGJSON.encoder().encode(saved), as: UTF8.self))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--check-updates") {
            Task {
                guard let updater = Self.updateStore else { exit(1) }
                await updater.check()
                print("Installed: \(updater.currentVersion), latest: \(updater.release?.version ?? "unknown"), available: \(updater.updateAvailable), verified download metadata: \(updater.release?.safeDownload != nil)")
                if let message = updater.message { print(message) }
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "--verify-update-file"), args.count > index + 1 {
                    do {
                        guard let asset = updater.release?.safeDownload else { throw UpdateError.invalidDownload }
                        try UpdateStore.verify(Data(contentsOf: URL(fileURLWithPath: args[index + 1])), asset: asset)
                        print("Downloaded release file: SHA-256 verified")
                    } catch { print(error.localizedDescription); exit(1) }
                }
                exit(updater.isError ? 1 : 0)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--read-shortcut-status") || ProcessInfo.processInfo.arguments.contains("--read-shortcut-power") {
            Task {
                do {
                    if ProcessInfo.processInfo.arguments.contains("--read-shortcut-status") {
                        let result = try await ReadBatteryStatusIntent().perform()
                        guard let json = result.value else { exit(1) }
                        print(json)
                    } else {
                        let result = try await ReadPowerFlowIntent().perform()
                        guard let json = result.value else { exit(1) }
                        print(json)
                    }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--read-power-flow") {
            if let sample = PowerFlowReader.read(), sample.isFresh(),
               sample.inputWatts != nil || sample.batteryWatts != nil {
                struct PowerFlowOutput: Encodable {
                    let available: Bool
                    let sampledAt: Date
                    let source: String
                    let inputWatts: Double?
                    let batteryWatts: Double?
                    let systemWatts: Double?
                    let adapterRatedWatts: Double?
                    let hardwarePercent: Double?
                }
                let output = PowerFlowOutput(
                    available: true,
                    sampledAt: sample.sampledAt,
                    source: sample.source,
                    inputWatts: sample.inputWatts,
                    batteryWatts: sample.batteryWatts,
                    systemWatts: sample.systemWatts,
                    adapterRatedWatts: sample.adapterRatedWatts,
                    hardwarePercent: sample.hardwarePercent
                )
                if let data = try? BGJSON.encoder().encode(output),
                   let string = String(data: data, encoding: .utf8) {
                    print(string)
                } else {
                    FileHandle.standardError.write(Data("Power-Flow-JSON konnte nicht erstellt werden.\n".utf8))
                    exit(1)
                }
            } else {
                print("{\"available\":false}")
            }
            exit(0)
        }
        AppPresence.shared.applyOnLaunch()
        Self.updateStore?.startAutomaticChecks()
        Self.apiStore?.startIfEnabled()
        GlobalHotKeys.shared.update(enabled: UserDefaults.standard.bool(forKey: GlobalHotKeys.appStorageKey))
        AppearancePreference.applyStored()
        guard AppPresence.isRunningFromBundle,
              !FileManager.default.fileExists(atPath: BGPaths.daemonBinary) else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("B-Guard einrichten")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView { [weak window] in window?.close() })
        window.center()
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct BatteryGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var statusStore: StatusStore
    @State private var configStore: ConfigStore
    @State private var historyStore: HistoryStore
    @State private var services = ServiceManager()
    @State private var updates: UpdateStore
    @State private var api: LocalAPIStore
    
    init() {
        let preview = DesignPreview.isRendering || ProcessInfo.processInfo.arguments.contains("--check-updates") || ProcessInfo.processInfo.arguments.contains("--read-power-flow") || ProcessInfo.processInfo.arguments.contains("--read-shortcut-status") || ProcessInfo.processInfo.arguments.contains("--read-shortcut-power") || ProcessInfo.processInfo.arguments.contains("--run")
        if !preview { BGuardShortcutsProvider.updateAppShortcutParameters() }
        let config = preview ? ConfigStore.preview : ConfigStore()
        let status = preview ? StatusStore.preview : StatusStore()
        let history = HistoryStore(preview: preview)
        let updater = UpdateStore(preferences: preview ? UserDefaults(suiteName: "BGuardPreview.\(UUID().uuidString)")! : .standard)
        let api = LocalAPIStore(config: config, status: status, history: history,
                                preferences: preview ? UserDefaults(suiteName: "BGuardAPIPreview.\(UUID().uuidString)")! : .standard)
        AppDelegate.apiStore = api
        _api = State(wrappedValue: api)
        AppDelegate.updateStore = updater
        _updates = State(wrappedValue: updater)
        AppDelegate.configStore = config
        let lidLock = LidLockGuard()
        status.onFreshStatus = { [weak history] fresh in
            history?.record(fresh)
            if !preview { lidLock.observe(fresh, enabled: UserDefaults.standard.bool(forKey: LidLockGuard.appStorageKey)) }
            if !preview {
                NetworkRuleMonitor.shared.poll { profile in
                    _ = try? AppDelegate.configStore?.performAPIAction(.init(action: .profile, profile: profile.rawValue))
                }
            }
        }
        if status.isDaemonActive { history.record(status.status) }
        _historyStore = State(wrappedValue: history)
        status.configRefresh = { [weak config] in config?.loadConfig() }
        status.configProvider = { [weak config] in
            config?.config ?? BGConfig()
        }
        _configStore = State(wrappedValue: config)
        _statusStore = State(wrappedValue: status)
    }
    
    @AppStorage("bg.showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(AccentPreference.appStorageKey) private var accent: AccentPreference = .system

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            PopoverContentView(
                statusStore: statusStore,
                configStore: configStore,
                historyStore: historyStore,
                updates: updates
            )
            .tint(accent.color)
        } label: {
            MenuBarLabelView(
                status: statusStore.status,
                isDaemonActive: statusStore.isDaemonActive,
                hardwarePercent: statusStore.powerFlow.flatMap { $0.isFresh() ? $0.hardwarePercent : nil },
                updateAvailable: updates.updateAvailable
            )
        }
        .menuBarExtraStyle(.window)

        Window("B-Guard", id: "dashboard") {
            DashboardView(statusStore: statusStore, configStore: configStore,
                          historyStore: historyStore, services: services, updates: updates, api: api)
                .tint(accent.color)
        }
        .defaultSize(width: 980, height: 760)

        Window("Updates & Neuigkeiten", id: "updates") {
            UpdatesView(updates: updates)
        }
        .defaultSize(width: 720, height: 780)

        Settings {
            PreferencesView(statusStore: statusStore, configStore: configStore, services: services, updates: updates, api: api)
                .frame(width: 620, height: 720)
        }
    }
}

struct MenuBarLabelView: View {
    let status: BGStatus
    let isDaemonActive: Bool
    var hardwarePercent: Double? = nil
    var updateAvailable = false
    @AppStorage("bg.menuBarDisplayOnBattery") private var menuBarDisplayOnBattery = ""
    @AppStorage(MenuBarIconStyle.appStorageKey) private var menuBarIconStyle: MenuBarIconStyle = .ring
    @AppStorage(MenuBarDisplayMode.appStorageKey) private var menuBarDisplay: MenuBarDisplayMode = .percent
    @AppStorage(MenuBarExtraItem.appStorageKey) private var menuBarExtras = ""
    @State private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var extraItems: [MenuBarExtraItem] { MenuBarExtraItem.decode(menuBarExtras) }
    /// Auf Akku optional eine eigene Anzeige, etwa Restlaufzeit statt Prozent.
    private var displayMode: MenuBarDisplayMode {
        let onBattery = isDaemonActive && !status.pluggedIn && status.state == .onBattery
        guard onBattery, let override = MenuBarDisplayMode(rawValue: menuBarDisplayOnBattery) else { return menuBarDisplay }
        return override
    }

    var body: some View {
        HStack(spacing: 5) {
            MenuBarIconView(
                style: menuBarIconStyle,
                status: status,
                isDaemonActive: isDaemonActive
            ).accessibilityHidden(true)
            
            if updateAvailable {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 9))
                    .foregroundStyle(Color.accentColor).help("Neue B-Guard-Version verfügbar")
            }

            let displayText = ([MenuBarDisplayFormatter.text(for: displayMode, status: status, isDaemonActive: isDaemonActive)]
                + MenuBarExtraFormatter.texts(for: extraItems, status: status, isDaemonActive: isDaemonActive, hardwarePercent: hardwarePercent))
                .filter { !$0.isEmpty }.joined(separator: " · ")
            if MenuBarExtraFormatter.showsLowPowerSymbol(for: extraItems, lowPowerModeEnabled: lowPowerModeEnabled) {
                Image(systemName: "leaf.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                    .accessibilityLabel(L("Low Power Mode aktiv"))
            }
            if !displayText.isEmpty {
                Text(displayText)
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .help(MenuBarDisplayFormatter.tooltip(for: menuBarDisplay, status: status, isDaemonActive: isDaemonActive, localize: true))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MenuBarAppearance.symbolDescriptor(style: menuBarIconStyle, status: status, isDaemonActive: isDaemonActive, localize: true).accessibilityDescription + ". " + MenuBarDisplayFormatter.voiceOverText(for: menuBarDisplay, status: status, isDaemonActive: isDaemonActive, localize: true) + (updateAvailable ? ". " + L("Neue B-Guard-Version verfügbar") + "." : ""))
    }
}
