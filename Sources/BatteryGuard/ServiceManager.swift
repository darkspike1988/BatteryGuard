import Foundation
import Observation
import ServiceManagement
import BatteryGuardShared

@MainActor
@Observable
final class ServiceManager {
    var isBusy = false
    var message: String?
    var isError = false

    /// Developer-ID-Builds enthalten die Dienst-Plist im Bundle. Dann registriert macOS den
    /// Dienst über SMAppService (macOS 13+): launchd startet ihn aus dem signierten Bundle
    /// und prüft die Signatur selbst; Freigabe unter Systemeinstellungen → Allgemein →
    /// Anmeldeobjekte. Ad-hoc-Community-Builds verwenden weiterhin das Installationsskript.
    static let daemonPlistName = BGPaths.daemonLabel + ".plist"

    static var bundledDaemon: SMAppService? {
        let plist = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(daemonPlistName)")
        guard FileManager.default.fileExists(atPath: plist.path) else { return nil }
        return SMAppService.daemon(plistName: daemonPlistName)
    }

    /// Ein früher per Skript installierter Dienst belegt dasselbe Label.
    static var legacyDaemonInstalled: Bool {
        FileManager.default.fileExists(atPath: BGPaths.daemonPlist)
    }

    static var isDaemonInstalled: Bool {
        if let service = bundledDaemon, service.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: BGPaths.daemonBinary)
    }

    func install() {
        guard let service = Self.bundledDaemon else { runScript(named: "install-daemon"); return }
        if Self.legacyDaemonInstalled {
            // Erst den Skript-Dienst entfernen (Administratorfreigabe), dann registrieren.
            runScript(named: "uninstall-daemon") { [weak self] succeeded in
                if succeeded { self?.register(service) }
            }
        } else {
            register(service)
        }
    }

    func uninstall() {
        guard let service = Self.bundledDaemon, service.status != .notRegistered else {
            runScript(named: "uninstall-daemon")
            return
        }
        isBusy = true
        message = nil
        // Beim Beenden stellt der Dienst über seinen SIGTERM-Failsafe den Normalbetrieb her.
        service.unregister { [weak self] error in
            let failure = error?.localizedDescription
            Task { @MainActor in
                self?.isBusy = false
                self?.isError = failure != nil
                self?.message = failure.map { L("Vorgang nicht abgeschlossen. %@", $0) }
                    ?? L("Dienst entfernt. macOS übernimmt das Laden.")
            }
        }
    }

    private func register(_ service: SMAppService) {
        do {
            try service.register()
        } catch {
            // Bereits registriert oder wartet auf Freigabe: Status entscheidet unten.
            if service.status != .enabled && service.status != .requiresApproval {
                isError = true
                message = L("Vorgang nicht abgeschlossen. %@", error.localizedDescription)
                return
            }
        }
        switch service.status {
        case .enabled:
            isError = false
            message = L("Dienst installiert und gestartet.")
        case .requiresApproval:
            isError = false
            message = L("Bitte den B-Guard-Dienst unter Systemeinstellungen → Allgemein → Anmeldeobjekte erlauben.")
            SMAppService.openSystemSettingsLoginItems()
        default:
            isError = true
            message = L("Der Dienst konnte nicht registriert werden. Bitte die App aus dem Programme-Ordner öffnen.")
        }
    }

    private func runScript(named name: String, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard !isBusy else { return }
        guard let path = Bundle.main.path(forResource: name, ofType: "sh") else {
            isError = true
            message = L("Installationsdatei fehlt. Bitte die gebaute B-Guard.app verwenden.")
            return
        }
        isBusy = true
        message = nil
        // Zwei getrennte Quoting-Schichten: Shell-Argument und AppleScript-String.
        let quotedPath = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "/bin/bash " + quotedPath
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escapedCommand)\" with administrator privileges"
        Task { [weak self] in
            let result = await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let pipe = Pipe()
                process.standardError = pipe
                process.standardOutput = FileHandle.nullDevice
                do {
                    try process.run()
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    return (process.terminationStatus == 0, String(data: errorData, encoding: .utf8) ?? "")
                } catch { return (false, error.localizedDescription) }
            }.value
            self?.isBusy = false
            self?.isError = !result.0
            self?.message = result.0 ? (name == "install-daemon" ? L("Dienst installiert und gestartet.") : L("Dienst entfernt. macOS übernimmt das Laden."))
                : L("Vorgang nicht abgeschlossen. %@", result.1.trimmingCharacters(in: .whitespacesAndNewlines))
            completion?(result.0)
        }
    }
}
