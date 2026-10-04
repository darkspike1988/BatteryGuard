import Foundation
import Observation

@MainActor
@Observable
final class ServiceManager {
    var isBusy = false
    var message: String?
    var isError = false

    func install() { runScript(named: "install-daemon") }
    func uninstall() { runScript(named: "uninstall-daemon") }

    private func runScript(named name: String) {
        guard !isBusy else { return }
        guard let path = Bundle.main.path(forResource: name, ofType: "sh") else {
            isError = true
            message = "Installationsdatei fehlt. Bitte die gebaute BatteryGuard.app verwenden."
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
            self?.message = result.0 ? (name == "install-daemon" ? "Dienst installiert und gestartet." : "Dienst entfernt. macOS übernimmt das Laden.")
                : "Vorgang nicht abgeschlossen. " + result.1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
