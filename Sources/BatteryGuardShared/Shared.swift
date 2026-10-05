import Foundation

/// Gemeinsamer Vertrag zwischen Menüleisten-App (User) und Daemon (root).
/// Status und Konfiguration sind lesbar; Änderungen laufen über authentifizierte lokale IPC.
public enum BGPaths {
    public static let directory = "/Library/Application Support/BatteryGuard"
    /// Root-eigen (0644); Änderungen nur durch den Einstellungsdienst.
    public static let config = directory + "/config.json"
    /// Vom Daemon geschrieben (0644), von der App gelesen.
    public static let status = directory + "/status.json"
    public static let daemonLabel = "com.batteryguard.daemon"
    public static let daemonPlist = "/Library/LaunchDaemons/com.batteryguard.daemon.plist"
    public static let daemonBinary = "/usr/local/libexec/batteryguardd"
}

/// Wie das Limit durchgesetzt wird.
public enum BGMode: String, Codable, CaseIterable, Sendable {
    /// Daemon wählt selbst: SMC-Ladesperre, falls vorhanden, sonst Pendel-Modus.
    case auto
    /// Nur beobachten: das native macOS-Ladelimit (Systemeinstellungen → Batterie) macht die Arbeit.
    case native
    /// Limit nur über den Netzteil-Schalter (CHIE) erzwingen (Sägezahn zwischen max-5 und max).
    case pendulum
    /// EXPERIMENTELL: natives Limit direkt im SMC (CHLT) auf den eigenen Wert setzen (nur root).
    case direct
}

public struct BGConfig: Codable, Equatable, Sendable {
    /// Schutz aktiv? false => Laden immer erlaubt, Adapter an.
    public var enabled: Bool = true
    /// Unter diesem Wert wird (wieder) geladen. Erlaubt 5...95.
    public var lowerLimit: Int = 20
    /// Ab diesem Wert wird das Laden gestoppt. Erlaubt 20...100, > lowerLimit.
    public var upperLimit: Int = 80
    /// Am Netzteil aktiv entladen (Adapter trennen), wenn Akku > upperLimit.
    public var activeDischargeAboveUpper: Bool = false
    /// Laden stoppen wenn Akku wärmer als dieser Wert (°C). 0 = aus.
    public var heatProtectionCelsius: Int = 0
    /// Einmalig voll laden (z. B. vor Reise). Daemon setzt es nach 100 % selbst zurück.
    public var chargeToFullOnce: Bool = false
    /// MagSafe LED steuern (Grün beim Halten)
    public var magsafeLed: Bool = true
    /// Durchsetzungs-Modus (siehe BGMode).
    public var mode: BGMode = .auto
    /// Zeitlich begrenzte Pause. Die ursprünglichen Schutzeinstellungen bleiben erhalten.
    public var pauseUntil: Date? = nil
    /// Reiseplanung: Vollladen startet drei Stunden vor diesem Termin.
    public var travelReadyAt: Date? = nil
    /// Manuelles Vollladen endet spätestens zu diesem Zeitpunkt.
    public var fullChargeUntil: Date? = nil

    /// Stable identities distinguish renewed requests even within one JSON timestamp second.
    public var fullChargeRequestID: UUID? = nil
    public var travelRequestID: UUID? = nil

    /// Aktiver P3-Spezialladesplan (Top-Up, Entladen, Halten).
    public var specialChargePlan: BGSpecialChargePlan? = nil

    public var awakeUntilLimitUntil: Date? = nil
    public var calibrationPlan: BGCalibrationPlan? = nil
    public var scheduledTasks: [BGScheduledTask] = []
    public var scheduleHistory: [BGScheduleRun] = []
    public var manualOverrideUntil: Date? = nil

    public init() {}

    // Tolerantes Decoding: fehlende Schlüssel (ältere Dateien) → Defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BGConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        lowerLimit = try c.decodeIfPresent(Int.self, forKey: .lowerLimit) ?? d.lowerLimit
        upperLimit = try c.decodeIfPresent(Int.self, forKey: .upperLimit) ?? d.upperLimit
        activeDischargeAboveUpper = try c.decodeIfPresent(Bool.self, forKey: .activeDischargeAboveUpper) ?? d.activeDischargeAboveUpper
        heatProtectionCelsius = try c.decodeIfPresent(Int.self, forKey: .heatProtectionCelsius) ?? d.heatProtectionCelsius
        chargeToFullOnce = try c.decodeIfPresent(Bool.self, forKey: .chargeToFullOnce) ?? d.chargeToFullOnce
        magsafeLed = try c.decodeIfPresent(Bool.self, forKey: .magsafeLed) ?? d.magsafeLed
        // Missing legacy values retain their default. Explicit unknown modes must
        // never silently enable active adapter switching.
        if let rawMode = try c.decodeIfPresent(String.self, forKey: .mode) {
            mode = BGMode(rawValue: rawMode) ?? .native
        } else { mode = d.mode }
        pauseUntil = try c.decodeIfPresent(Date.self, forKey: .pauseUntil)
        travelReadyAt = try c.decodeIfPresent(Date.self, forKey: .travelReadyAt)
        fullChargeUntil = try c.decodeIfPresent(Date.self, forKey: .fullChargeUntil)
        fullChargeRequestID = try c.decodeIfPresent(UUID.self, forKey: .fullChargeRequestID)
        travelRequestID = try c.decodeIfPresent(UUID.self, forKey: .travelRequestID)
        awakeUntilLimitUntil = try c.decodeIfPresent(Date.self, forKey: .awakeUntilLimitUntil)
        calibrationPlan = try? c.decodeIfPresent(BGCalibrationPlan.self, forKey: .calibrationPlan)
        scheduledTasks = try c.decodeIfPresent([BGScheduledTask].self, forKey: .scheduledTasks) ?? []
        scheduleHistory = try c.decodeIfPresent([BGScheduleRun].self, forKey: .scheduleHistory) ?? []
        manualOverrideUntil = try c.decodeIfPresent(Date.self, forKey: .manualOverrideUntil)
        do {
            if let decoded = try c.decodeIfPresent(BGSpecialChargePlan.self, forKey: .specialChargePlan) {
                specialChargePlan = decoded.isValid ? decoded : nil
            } else {
                specialChargePlan = nil
            }
        } catch {
            specialChargePlan = nil
        }
    }

    /// Daemon MUSS jede gelesene Config durch diese Funktion schicken (Konfiguration ist root-eigen, Änderungen sind authentifiziert).
    public func sanitized() -> BGConfig {
        var c = self
        c.lowerLimit = min(max(c.lowerLimit, 5), 95)
        c.upperLimit = min(max(c.upperLimit, 20), 100)
        if c.upperLimit <= c.lowerLimit { c.lowerLimit = max(5, c.upperLimit - 5) }
        c.heatProtectionCelsius = (c.heatProtectionCelsius == 0) ? 0 : min(max(c.heatProtectionCelsius, 30), 50)
        if !c.chargeToFullOnce { c.fullChargeRequestID = nil }
        if c.travelReadyAt == nil { c.travelRequestID = nil }
        if let plan = c.specialChargePlan {
            if !plan.isValid {
                c.specialChargePlan = nil
            }
        }
        if c.scheduledTasks.count > 50 || Set(c.scheduledTasks.map(\.id)).count != c.scheduledTasks.count { c.scheduledTasks = [] }
        c.scheduleHistory = Array(c.scheduleHistory.suffix(100))
        return c
    }
}


public enum BGChargeState: String, Codable, Sendable {
    case charging          // lädt normal
    case holding           // Laden gestoppt, Netzteil versorgt (Limit erreicht)
    case discharging       // Adapter getrennt, Akku entlädt aktiv am Kabel
    case onBattery         // kein Netzteil angeschlossen
    case unsupported       // keine passenden SMC-Keys gefunden
    case disabled          // Schutz aus
}

public struct BGStatus: Codable, Equatable, Sendable {
    public var configurationNotice: String? = nil
    /// Nur lesend erkannter nativer macOS-SMC-Grenzwert, falls verfügbar.
    public var nativeChargeLimit: Int? = nil
    public var percent: Int = 0
    public var percentAvailable: Bool? = nil
    public var externalPowerAvailable: Bool? = nil
    public var awakeUntilLimitActive: Bool? = nil
    public var hasBatteryPercent: Bool { percentAvailable != false }
    public var hasExternalPower: Bool { externalPowerAvailable != false }
    public var pluggedIn: Bool = false
    public var isChargingHardware: Bool = false
    public var state: BGChargeState = .unsupported
    public var temperatureCelsius: Double? = nil
    public var cycleCount: Int? = nil
    /// Gesundheit in % (MaxCapacity / DesignCapacity)
    public var healthPercent: Int? = nil
    public var watts: Double? = nil
    public var voltage: Double? = nil
    public var amperage: Double? = nil
    public var timeRemainingMinutes: Int? = nil
    public var maxCapacityMah: Int? = nil
    public var designCapacityMah: Int? = nil
    public var smcKeysDetected: [String] = []
    public var daemonVersion: String = "0.2.0"
    public var updatedAt: Date = Date()
    public var message: String? = nil

    public init() {}
}

public enum BGJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
