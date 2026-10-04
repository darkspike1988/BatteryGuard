import AppKit
import SwiftUI
import BatteryGuardShared

/// Entwicklerrendering aus den echten Views. Keine Bildschirmaufnahme und kein
/// Zugriff auf Konfiguration, SMC oder Verlauf des Benutzers.
@MainActor
enum DesignPreview {
    static var isRendering: Bool { ProcessInfo.processInfo.arguments.contains("--render-preview") }

    static func render() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--render-preview"), args.count > index + 1 else { exit(2) }
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fputs("\(error)\n", stderr); exit(1) }
        let config = ConfigStore.preview
        let status = StatusStore.preview
        if args.contains("--native") {
            config.config.mode = .native
            status.status.nativeChargeLimit = 80
            status.status.state = .disabled
        }
        if args.contains("--desktop") {
            config.activateProfile(.desk)
            status.status.nativeChargeLimit = 80
            status.status.state = .disabled
            status.status.message = "Monitor-/Deckelschutz: Netzteil bleibt verbunden. Ohne separate Ladesperre übernimmt macOS das Ladelimit."
        }
        if args.contains("--offline") { status.isDaemonActive = false }
        if args.contains("--travel") { config.scheduleTravel(readyAt: Date().addingTimeInterval(12 * 3600)) }
        if args.contains("--warm") {
            status.status.temperatureCelsius = 44
            status.status.state = .holding
            status.status.message = "Hitzeschutz aktiv. Laden wird nach dem Abkühlen fortgesetzt."
        }
        let history = HistoryStore(preview: true, emptyPreview: args.contains("--empty-history"))
        let services = ServiceManager()
        let appearance: NSAppearance.Name = args.contains("--dark") ? .darkAqua : .aqua
        NSApplication.shared.appearance = NSAppearance(named: appearance)
        let theme: ColorScheme = args.contains("--dark") ? .dark : .light
        do {
            let updatePreferences = UserDefaults(suiteName: "BGuardPreview.\(UUID().uuidString)")!
            updatePreferences.set(args.contains("--menu-metrics"), forKey: "bg.menuShowTemperature")
            updatePreferences.set(args.contains("--menu-metrics"), forKey: "bg.menuShowPower")
            updatePreferences.set(args.contains("--menu-metrics"), forKey: "bg.menuShowHealth")
            let updater = UpdateStore(preferences: updatePreferences)
            let api = LocalAPIStore(config: config, status: status, history: history, preferences: updatePreferences)
            if args.contains("--update-available") {
                let json = #"{"tag_name":"v0.4.0","body":"Ladeprofile verbessert.\nSchlaf-/Aufwachverhalten robuster.\nNeue Möglichkeiten für deinen Alltag.","draft":false,"prerelease":false,"assets":[]}"#
                updater.release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
                updater.checkedAt = Date()
                updater.message = "B-Guard 0.4.0 ist verfügbar."
            }
            try renderView(DashboardView(statusStore: status, configStore: config, historyStore: history, services: services, updates: updater, api: api)
                .defaultAppStorage(updatePreferences).environment(\.colorScheme, theme), size: NSSize(width: args.contains("--small") ? 780 : 980, height: args.contains("--small") ? 600 : 1060),
                           to: directory.appendingPathComponent("overview.png"))
            try renderView(HistoryView(history: history, currentConfig: config.config)
                .defaultAppStorage(updatePreferences).environment(\.colorScheme, theme), size: NSSize(width: 790, height: 760),
                           to: directory.appendingPathComponent("history.png"))
            try renderView(PopoverContentView(statusStore: status, configStore: config, historyStore: history, updates: updater)
                .defaultAppStorage(updatePreferences).environment(\.colorScheme, theme), size: NSSize(width: 370, height: 575),
                           to: directory.appendingPathComponent("menu.png"))
            try renderView(PreferencesView(statusStore: status, configStore: config, services: services, updates: updater, api: api)
                .defaultAppStorage(updatePreferences).environment(\.colorScheme, theme), size: NSSize(width: 660, height: 1060),
                           to: directory.appendingPathComponent("settings.png"))
            try renderView(SetupView(close: {}).defaultAppStorage(updatePreferences).environment(\.colorScheme, theme),
                           size: NSSize(width: 480, height: 340),
                           to: directory.appendingPathComponent("setup.png"))
            try renderView(UpdatesView(updates: updater).defaultAppStorage(updatePreferences).environment(\.colorScheme, theme),
                           size: NSSize(width: 720, height: 900),
                           to: directory.appendingPathComponent("updates.png"))
            for mode in MenuBarDisplayMode.allCases {
                let labelPreferences = UserDefaults(suiteName: "BGuardLabelPreview.\(UUID().uuidString)")!
                labelPreferences.set(mode.rawValue, forKey: MenuBarDisplayMode.appStorageKey)
                try renderView(MenuBarLabelView(status: status.status, isDaemonActive: status.isDaemonActive, updateAvailable: updater.updateAvailable)
                    .defaultAppStorage(labelPreferences).environment(\.colorScheme, theme),
                    size: NSSize(width: 160, height: 36),
                    to: directory.appendingPathComponent("label-\(mode.rawValue).png"))
            }
            for style in MenuBarIconStyle.allCases {
                for state in [BGChargeState.charging, .holding, .onBattery, .disabled, .unsupported] {
                    var sample = status.status
                    sample.state = state
                    sample.pluggedIn = state != .onBattery
                    sample.isChargingHardware = state == .charging
                    try renderView(MenuBarIconView(style: style, status: sample, isDaemonActive: true)
                        .environment(\.colorScheme, theme), size: NSSize(width: 48, height: 36),
                        to: directory.appendingPathComponent("icon-\(style.rawValue)-\(state.rawValue).png"))
                }
            }
            print("Preview rendered: \(directory.path)")
            exit(0)
        } catch { fputs("\(error)\n", stderr); exit(1) }
    }

    private static func renderView<Content: View>(_ view: Content, size: NSSize, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
