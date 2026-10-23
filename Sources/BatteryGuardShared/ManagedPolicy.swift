import Foundation

/// Von der IT per Konfigurationsprofil (MDM) vorgegebene Werte für `com.batteryguard.app`.
/// macOS legt sie unter `/Library/Managed Preferences/com.batteryguard.app.plist` ab.
///
/// Schlüssel: `LockSettings` (Bool, alle Änderungen sperren), `UpperLimit`, `LowerLimit` (Int),
/// `Mode` (`auto`, `native`, `pendulum`, `systemLimit`), `ProtectionEnabled` (Bool).
public struct BGManagedPolicy: Codable, Equatable, Sendable {
    public var lockSettings: Bool
    public var upperLimit: Int?
    public var lowerLimit: Int?
    public var mode: BGMode?
    public var protectionEnabled: Bool?

    public static let path = "/Library/Managed Preferences/com.batteryguard.app.plist"

    public init(lockSettings: Bool = false, upperLimit: Int? = nil, lowerLimit: Int? = nil,
                mode: BGMode? = nil, protectionEnabled: Bool? = nil) {
        self.lockSettings = lockSettings
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
        self.mode = mode
        self.protectionEnabled = protectionEnabled
    }

    /// nil, wenn kein Profil installiert ist oder es keine bekannten Schlüssel enthält.
    public static func load(path: String = path) -> BGManagedPolicy? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return parse(plist)
    }

    public static func parse(_ plist: [String: Any]) -> BGManagedPolicy? {
        func int(_ key: String) -> Int? { (plist[key] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue } }
        func bool(_ key: String) -> Bool? { (plist[key] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil } }
        let policy = BGManagedPolicy(lockSettings: bool("LockSettings") ?? false, upperLimit: int("UpperLimit"),
                                     lowerLimit: int("LowerLimit"),
                                     mode: (plist["Mode"] as? String).flatMap(BGMode.init(rawValue:)).flatMap { $0 == .direct ? nil : $0 },
                                     protectionEnabled: bool("ProtectionEnabled"))
        return policy == BGManagedPolicy() ? nil : policy
    }

    public var hasValues: Bool { upperLimit != nil || lowerLimit != nil || mode != nil || protectionEnabled != nil }

    /// Setzt die vorgegebenen Werte durch; `sanitized()` hält die Grenzen gültig.
    public func apply(to config: BGConfig) -> BGConfig {
        var result = config
        if let upperLimit { result.upperLimit = upperLimit }
        if let lowerLimit { result.lowerLimit = lowerLimit }
        if let mode { result.mode = mode }
        if let protectionEnabled { result.enabled = protectionEnabled }
        return result.sanitized()
    }
}
