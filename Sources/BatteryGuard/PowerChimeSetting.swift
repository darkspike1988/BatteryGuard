import Foundation

/// macOS-Ladeton beim Anstecken (Domain `com.apple.PowerChime`, Benutzereinstellung).
enum PowerChimeSetting {
    // String-Konstanten sind Sendable; CFString entsteht erst beim Aufruf.
    private static let domainName = "com.apple.PowerChime"
    private static let keyName = "ChimeOnNoHardware"
    private static var domain: CFString { domainName as CFString }
    private static var key: CFString { keyName as CFString }

    static var isMuted: Bool {
        CFPreferencesCopyAppValue(key, domain) as? Bool ?? false
    }

    /// Schreibt die Einstellung und startet PowerChime neu, damit sie sofort gilt.
    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        CFPreferencesSetAppValue(key, muted as CFBoolean, domain)
        guard CFPreferencesAppSynchronize(domain) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["PowerChime"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return isMuted == muted
    }
}
