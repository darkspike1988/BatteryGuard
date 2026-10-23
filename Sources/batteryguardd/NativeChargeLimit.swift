import Foundation
import BatteryGuardShared
#if canImport(notify)
import notify
#endif

/// Die Methoden von `PowerUISmartChargeClient` (privates PowerUI.framework), die B-Guard nutzt.
/// Die Klasse wird zur Laufzeit geladen; deshalb ein Protokoll statt eines Headers.
@objc private protocol PowerUISmartChargeClient {
    @objc(initWithClientName:) func initWithClientName(_ name: String) -> AnyObject
    @objc(isMCLSupported) func isMCLSupported() -> Bool
    @objc(isMCLCurrentlyEnabled:) func isMCLCurrentlyEnabled(_ error: NSErrorPointer) -> UInt64
    @objc(enableMCL:) func enableMCL(_ error: NSErrorPointer) -> Bool
    @objc(getMCLLimitWithError:) func getMCLLimit(_ error: NSErrorPointer) -> UInt8
}

/// Setzt das macOS-Ladelimit (Systemeinstellungen → Batterie, ab macOS 26.4).
///
/// Seit der Firmware von macOS 27 ist die SMC-Ladesperre gesperrt. Was bleibt, ist der Weg,
/// den macOS selbst nutzt: PowerUIAgent (root) liest `mclLimitValue` aus seinem
/// Einstellungsbereich und gibt den Wert an powerd weiter. Nach der Darwin-Benachrichtigung
/// `com.apple.smartcharging.defaultschanged` lädt der Agent die Einstellungen neu; dabei prüft
/// er den Bereich 80–100 % nicht, deshalb sind auch niedrigere Werte möglich. Nicht von Apple
/// dokumentiert; dieselbe Technik nutzen BatLimit und Battery Toolkit für macOS 27.
/// Der Wert gilt auch im Schlaf und während der Dienst gestoppt ist.
public final class NativeChargeLimit: NativeChargeLimitDriving, @unchecked Sendable {
    static let domain = "com.apple.smartcharging.topoffprotection" as CFString
    static let changedNotification = "com.apple.smartcharging.defaultschanged"
    private static let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI"
    private static let limitKey = "mclLimitValue" as CFString
    private static let featureStateKey = "MCLFeatureState" as CFString
    /// „Jetzt vollständig laden“ im Batteriemenü; solange der Schlüssel existiert, gilt kein Limit.
    private static let tempDisabledKey = "MCLTempDisabledUntilDate" as CFString
    /// powerd hebt diesen Zustand während der Kalibrierungsladung auf 1 (ohne Rechte lesbar).
    static let chargingToFullOverride = "com.apple.system.powersources.chargingtofulloverride"

    private let backupURL: URL
    private let lock = NSLock()
    private var client: PowerUISmartChargeClient?

    public init(backupURL: URL = URL(fileURLWithPath: BGPaths.directory).appendingPathComponent("native-limit-before.txt")) {
        self.backupURL = backupURL
    }

    /// Direkt nach dem Start kann der Agent noch „nicht unterstützt“ melden; deshalb bei jeder
    /// Abfrage neu fragen, statt ein Nein zu merken.
    public var isSupported: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadedClient()?.isMCLSupported() ?? false
    }

    public var hasTakenControl: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    public func currentLimit() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return agentLimit()
    }

    public func apply(_ percent: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let client = loadedClient(), client.isMCLSupported() else { return false }
        let value = min(max(percent, ControllerLogic.nativeLimitAbsoluteMinimum), 100)
        if !hasTakenControl {
            // Den Wert vor der Übernahme sichern; zurückgegeben wird mindestens 80 %.
            let original = isEnabled(client) ? agentLimit() ?? 100 : 100
            do {
                try String(min(max(original, ControllerLogic.nativeLimitSystemMinimum), 100))
                    .write(to: backupURL, atomically: true, encoding: .utf8)
            } catch { return false }
        }
        return write(value, client: client)
    }

    @discardableResult
    public func release() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let text = try? String(contentsOf: backupURL, encoding: .utf8) else { return true }
        let original = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 100
        let value = min(max(original, ControllerLogic.nativeLimitSystemMinimum), 100)
        guard let client = loadedClient(), write(value, client: client) else { return false }
        try? FileManager.default.removeItem(at: backupURL)
        return true
    }

    /// macOS lädt gerade zur Kalibrierung voll und setzt das Limit dafür aus.
    public static func macOSChargingToFull() -> Bool? {
        #if canImport(notify)
        var token: Int32 = 0
        guard notify_register_check(chargingToFullOverride, &token) == NOTIFY_STATUS_OK else { return nil }
        defer { notify_cancel(token) }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return nil }
        return state != 0
        #else
        return nil
        #endif
    }

    // MARK: - Intern (unter `lock`)

    private func loadedClient() -> PowerUISmartChargeClient? {
        if let client { return client }
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        let object = unsafeBitCast(allocated, to: PowerUISmartChargeClient.self).initWithClientName(BGPaths.daemonLabel)
        client = unsafeBitCast(object, to: PowerUISmartChargeClient.self)
        return client
    }

    private func agentLimit() -> Int? {
        guard let client = loadedClient() else { return nil }
        var error: NSError?
        let value = client.getMCLLimit(&error)
        return error == nil ? Int(value) : nil
    }

    private func isEnabled(_ client: PowerUISmartChargeClient) -> Bool {
        var error: NSError?
        return client.isMCLCurrentlyEnabled(&error) != 0 && error == nil
    }

    private func write(_ value: Int, client: PowerUISmartChargeClient) -> Bool {
        // Ein Wert allein wirkt nicht, solange das Limit in den Systemeinstellungen aus ist.
        if !isEnabled(client) {
            var error: NSError?
            _ = client.enableMCL(&error)
            if !isEnabled(client) {
                CFPreferencesSetAppValue(Self.featureStateKey, 1 as CFNumber, Self.domain)
            }
        }
        CFPreferencesSetAppValue(Self.tempDisabledKey, nil, Self.domain)
        CFPreferencesSetAppValue(Self.limitKey, value as CFNumber, Self.domain)
        guard CFPreferencesAppSynchronize(Self.domain) else { return false }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(Self.changedNotification as CFString),
                                             nil, nil, true)
        // Der Agent lädt asynchron neu. Ein still ignoriertes Limit hieße Laden bis 100 %,
        // während B-Guard etwas anderes anzeigt – deshalb kurz nachprüfen.
        for _ in 0..<20 {
            if agentLimit() == value { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
