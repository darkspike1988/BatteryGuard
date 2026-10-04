import SwiftUI
import AppKit
import BatteryGuardShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var configStore: ConfigStore?
    @MainActor static weak var updateStore: UpdateStore?
    @MainActor static weak var apiStore: LocalAPIStore?
    private var setupWindow: NSWindow?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.configStore?.flushPendingSave()
        Self.updateStore?.stopAutomaticChecks()
        Self.apiStore?.stop()
        return .terminateNow
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if DesignPreview.isRendering { DesignPreview.render(); return }
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
        guard AppPresence.isRunningFromBundle,
              !FileManager.default.fileExists(atPath: BGPaths.daemonBinary) else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "B-Guard einrichten"
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
        let preview = DesignPreview.isRendering || ProcessInfo.processInfo.arguments.contains("--check-updates") || ProcessInfo.processInfo.arguments.contains("--read-power-flow")
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
        status.onFreshStatus = { [weak history] in history?.record($0) }
        if status.isDaemonActive { history.record(status.status) }
        _historyStore = State(wrappedValue: history)
        status.configRefresh = { [weak config] in config?.loadConfig() }
        status.configProvider = { [weak config] in
            config?.config ?? BGConfig()
        }
        _configStore = State(wrappedValue: config)
        _statusStore = State(wrappedValue: status)
    }
    
    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(
                statusStore: statusStore,
                configStore: configStore,
                historyStore: historyStore,
                updates: updates
            )
        } label: {
            MenuBarLabelView(
                status: statusStore.status,
                isDaemonActive: statusStore.isDaemonActive,
                updateAvailable: updates.updateAvailable
            )
        }
        .menuBarExtraStyle(.window)

        Window("B-Guard", id: "dashboard") {
            DashboardView(statusStore: statusStore, configStore: configStore,
                          historyStore: historyStore, services: services, updates: updates, api: api)
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
    var updateAvailable = false
    @AppStorage(MenuBarIconStyle.appStorageKey) private var menuBarIconStyle: MenuBarIconStyle = .ring
    @AppStorage(MenuBarDisplayMode.appStorageKey) private var menuBarDisplay: MenuBarDisplayMode = .percent
    
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

            let displayText = MenuBarDisplayFormatter.text(for: menuBarDisplay, status: status, isDaemonActive: isDaemonActive)
            if !displayText.isEmpty {
                Text(displayText)
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .help(MenuBarDisplayFormatter.tooltip(for: menuBarDisplay, status: status, isDaemonActive: isDaemonActive))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MenuBarAppearance.symbolDescriptor(style: menuBarIconStyle, status: status, isDaemonActive: isDaemonActive).accessibilityDescription + ". " + MenuBarDisplayFormatter.voiceOverText(for: menuBarDisplay, status: status, isDaemonActive: isDaemonActive) + (updateAvailable ? ". Neue B-Guard-Version verfügbar." : ""))
    }
}
