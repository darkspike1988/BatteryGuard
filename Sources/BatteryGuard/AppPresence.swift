import Foundation
import AppKit
import ServiceManagement
import Observation

/// Verwaltet die Systempräsenz von BatteryGuard:
/// - Autostart bei der Anmeldung (SMAppService)
/// - Sichtbarkeit im Dock (NSApplication.ActivationPolicy)
/// - Initialer Setup beim ersten Start
@MainActor
@Observable
public final class AppPresence {
    public static let shared = AppPresence()

    private static let showInDockKey = "bg.showInDock"
    private static let didFirstLaunchKey = "bg.didFirstLaunch"

    /// Letzte Fehlermeldung bei Systemoperationen
    public var lastError: String? = nil

    /// Zeigt an, ob der Benutzer den Autostart in den Systemeinstellungen genehmigen muss
    public private(set) var launchAtLoginNeedsApproval: Bool = false

    /// Interne Eigenschaft zur Beobachtbarkeit externer SMAppService-Statusänderungen
    private var _statusChangeToken: Int = 0

    /// Gibt an, ob die App aus einem echten App-Bundle mit Bundle-Identifier ausgeführt wird
    public static var isRunningFromBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Autostart-Status via SMAppService
    public var launchAtLogin: Bool {
        get {
            _ = _statusChangeToken
            guard Self.isRunningFromBundle else { return false }
            return SMAppService.mainApp.status == .enabled
        }
        set {
            guard Self.isRunningFromBundle else {
                lastError = "Autostart kann nicht registriert werden: Die Anwendung läuft nicht aus einem App-Bundle (z. B. via 'swift run')."
                return
            }

            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                lastError = nil
            } catch {
                lastError = "Fehler beim Konfigurieren des Autostarts: \(error.localizedDescription)"
            }

            refreshLaunchAtLoginStatus()
            _statusChangeToken &+= 1
        }
    }

    /// Steuert, ob BatteryGuard im macOS-Dock sichtbar ist
    public var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: Self.showInDockKey)
            applyDockPolicy()
        }
    }

    private init() {
        self.showInDock = UserDefaults.standard.bool(forKey: Self.showInDockKey)
        refreshLaunchAtLoginStatus()
    }

    /// Aktualisiert den Genehmigungsstatus für den Autostart
    public func refreshLaunchAtLoginStatus() {
        guard Self.isRunningFromBundle else {
            launchAtLoginNeedsApproval = false
            return
        }
        let status = SMAppService.mainApp.status
        launchAtLoginNeedsApproval = (status == .requiresApproval)
    }

    /// Öffnet die macOS-Systemeinstellungen im Bereich "Anmeldeobjekte"
    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Wendet die Dock-Sichtbarkeit gemäß aktueller Einstellung an
    public func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    /// Führt die Initialisierung beim Start aus:
    /// - Beim allerersten Start wird der Autostart automatisch aktiviert
    /// - Gespeicherte Dock-Richtlinie wird auf die App angewendet
    public func applyOnLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.object(forKey: Self.didFirstLaunchKey) != nil
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: Self.didFirstLaunchKey)
            if Self.isRunningFromBundle {
                self.launchAtLogin = true
            }
        }

        applyDockPolicy()
        refreshLaunchAtLoginStatus()
    }
}
