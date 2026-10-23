import Foundation

/// Sicherung aller dauerhaften Einstellungen. Laufende Aufträge (Pause, Reise, Vollladen, Sonderaktionen),
/// Verläufe und Zeitplan-Ergebnisse gehören nicht dazu.
public struct BGSettingsBackup: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maxBytes = 512 * 1024

    public var version: Int
    public var createdAt: Date
    public var config: BGConfig
    /// App-Präferenzen mit Präfix `bg.` (Darstellung, Mitteilungen, Menüleiste).
    public var preferences: [String: BGPreferenceValue]

    public init(config: BGConfig, preferences: [String: BGPreferenceValue], createdAt: Date = Date()) {
        self.version = Self.currentVersion
        self.createdAt = createdAt
        self.config = config.portable()
        self.preferences = preferences.filter { $0.key.hasPrefix("bg.") }
    }

    public static func decode(_ data: Data) throws -> BGSettingsBackup {
        guard data.count <= maxBytes else { throw BGChargingActionError.invalidRequest("Die Sicherung ist zu groß.") }
        let backup = try BGJSON.decoder().decode(BGSettingsBackup.self, from: data)
        guard backup.version == currentVersion else { throw BGChargingActionError.invalidRequest("Unbekannte Version der Sicherung.") }
        return backup
    }
}

/// Einfache, typsichere Präferenzwerte für die Sicherung.
public enum BGPreferenceValue: Codable, Equatable, Sendable {
    case bool(Bool), int(Int), double(Double), string(String), data(Data)

    public init?(_ value: Any) {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): self = .bool(number.boolValue)
        case let number as NSNumber where CFNumberIsFloatType(number): self = .double(number.doubleValue)
        case let number as NSNumber: self = .int(number.intValue)
        case let string as String: self = .string(string)
        case let data as Data: self = .data(data)
        default: return nil
        }
    }

    public var value: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        case .data(let value): value
        }
    }
}

public extension BGConfig {
    /// Nur dauerhafte Einstellungen; laufende Aufträge und Verläufe werden zurückgesetzt.
    func portable() -> BGConfig {
        var c = self
        c.pauseUntil = nil
        c.travelReadyAt = nil
        c.travelRequestID = nil
        c.chargeToFullOnce = false
        c.fullChargeUntil = nil
        c.fullChargeRequestID = nil
        c.specialChargePlan = nil
        c.calibrationPlan = nil
        c.awakeUntilLimitUntil = nil
        c.manualOverrideUntil = nil
        c.scheduleHistory = []
        c.scheduledTasks = c.scheduledTasks.map { BGScheduledTask(schedule: $0.schedule, enabled: $0.enabled,
                                                                    catchUp: $0.catchUp, action: $0.action) }
        return c.sanitized()
    }

    /// Übernimmt die dauerhaften Einstellungen einer Sicherung; laufende Aufträge bleiben erhalten.
    func applyingPortable(from backup: BGConfig) -> BGConfig {
        var c = self
        let source = backup.portable()
        c.enabled = source.enabled
        c.lowerLimit = source.lowerLimit
        c.upperLimit = source.upperLimit
        c.activeDischargeAboveUpper = source.activeDischargeAboveUpper
        c.heatProtectionCelsius = source.heatProtectionCelsius
        c.coldProtectionCelsius = source.coldProtectionCelsius
        c.magsafeLed = source.magsafeLed
        c.magsafeLedOff = source.magsafeLedOff
        c.mode = source.mode
        c.desktopProfileEnabled = source.desktopProfileEnabled
        c.desktopProfile = source.desktopProfile
        c.lowPowerModeRule = source.lowPowerModeRule
        c.highPowerModeRule = source.highPowerModeRule
        c.preventSleepWhileDischarging = source.preventSleepWhileDischarging
        c.stopChargingWhenSleeping = source.stopChargingWhenSleeping
        c.allowLimitsBelowSystemMinimum = source.allowLimitsBelowSystemMinimum
        c.keepAwakeWhenLidClosed = source.keepAwakeWhenLidClosed
        return c.sanitized()
    }
}
