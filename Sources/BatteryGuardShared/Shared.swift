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
    /// macOS-Limit: setzt Apples natives Ladelimit (ab macOS 26/27) auf den nächsten erlaubten Wert.
    /// Für Macs ohne SMC-Ladesperre; ältere Dienste lesen den Wert als `.native`.
    case systemLimit
}

/// Abbildung eines B-Guard-Ziels auf die von macOS angebotenen Ladelimits.
public enum BGSystemChargeLimit {
    /// Kleinster erlaubter Wert, der das Ziel nicht unterschreitet; sonst der größte erlaubte Wert.
    public static func target(for percent: Int, available: [Int]) -> Int? {
        let sorted = available.filter { (1...100).contains($0) }.sorted()
        return sorted.first { $0 >= percent } ?? sorted.last
    }
}

/// Für welche Stromquelle ein macOS-Energiemodus gelten soll. `.off` lässt die Systemeinstellung unberührt.
public enum BGPowerModeRule: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, always, onBattery, onAdapter
    public var id: String { rawValue }
    public var appliesOnBattery: Bool { self == .always || self == .onBattery }
    public var appliesOnAdapter: Bool { self == .always || self == .onAdapter }
    public var localizedTitle: String {
        switch self {
        case .off: BGLocalized("Nicht steuern")
        case .always: BGLocalized("Immer")
        case .onBattery: BGLocalized("Nur auf Akku")
        case .onAdapter: BGLocalized("Nur am Netzteil")
        }
    }
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
    /// Solange ein externer Monitor verbunden ist, gilt das gewählte Profil nur für die Ladegrenzen.
    /// Es ändert weder das gespeicherte Profil noch Pause, Reise- oder Sonderpläne.
    public var desktopProfileEnabled: Bool = false
    public var desktopProfile: BGProfile? = nil
    /// Altes Feld für Dienste vor 0.6.0; spiegelt `lowPowerModeRule == .onBattery`.
    public var lowPowerModeOnBattery: Bool = false
    /// Low Power Mode je Stromquelle über `pmset` (nur wenn ausdrücklich aktiviert).
    public var lowPowerModeRule: BGPowerModeRule = .off
    /// High Power Mode je Stromquelle; nur auf Macs mit `pmset powermode`. Low Power Mode hat Vorrang.
    public var highPowerModeRule: BGPowerModeRule = .off
    /// Systemschlaf während aktivem Entladen kurzzeitig verhindern (opt-in, zeitlich begrenzt).
    public var preventSleepWhileDischarging: Bool = false

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
        desktopProfileEnabled = try c.decodeIfPresent(Bool.self, forKey: .desktopProfileEnabled) ?? d.desktopProfileEnabled
        if let rawProfile = try c.decodeIfPresent(String.self, forKey: .desktopProfile) {
            desktopProfile = BGProfile(rawValue: rawProfile)
        } else { desktopProfile = nil }
        lowPowerModeOnBattery = try c.decodeIfPresent(Bool.self, forKey: .lowPowerModeOnBattery) ?? d.lowPowerModeOnBattery
        // Unbekannte Regeln schalten nie einen Modus ein; fehlende übernehmen das alte Feld.
        if let rawRule = try c.decodeIfPresent(String.self, forKey: .lowPowerModeRule) {
            lowPowerModeRule = BGPowerModeRule(rawValue: rawRule) ?? .off
        } else { lowPowerModeRule = lowPowerModeOnBattery ? .onBattery : .off }
        if let rawRule = try c.decodeIfPresent(String.self, forKey: .highPowerModeRule) {
            highPowerModeRule = BGPowerModeRule(rawValue: rawRule) ?? .off
        } else { highPowerModeRule = d.highPowerModeRule }
        lowPowerModeOnBattery = lowPowerModeRule == .onBattery
        preventSleepWhileDischarging = try c.decodeIfPresent(Bool.self, forKey: .preventSleepWhileDischarging) ?? d.preventSleepWhileDischarging
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
        c.lowPowerModeOnBattery = c.lowPowerModeRule == .onBattery
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
    /// Additive, normalized diagnostic values. Missing for legacy daemons.
    public var measurements: BGBatteryMeasurements? = nil
    public var configurationNotice: String? = nil
    /// Nur lesend erkannter nativer macOS-SMC-Grenzwert, falls verfügbar.
    public var nativeChargeLimit: Int? = nil
    /// Tatsächlich angewandte Grenzen nach Pause, Reise, Sonderplan und Monitorprofil.
    public var effectiveLowerLimit: Int? = nil
    public var effectiveUpperLimit: Int? = nil
    public var externalDisplayConnected: Bool? = nil
    public var lidClosed: Bool? = nil
    public var adapterDisconnectAllowed: Bool? = nil
    public var desktopProfileActive: Bool? = nil
    public var percent: Int = 0
    public var percentAvailable: Bool? = nil
    public var externalPowerAvailable: Bool? = nil
    public var awakeUntilLimitActive: Bool? = nil
    /// Ob dieser Mac `pmset powermode` (und damit High Power Mode) anbietet.
    public var highPowerModeSupported: Bool? = nil
    /// Von macOS angebotene native Ladelimits; leer oder nil, wenn der macOS-Limit-Modus nicht verfügbar ist.
    public var systemChargeLimits: [Int]? = nil
    /// Zuletzt gelesenes natives macOS-Ladelimit über PowerUI (unabhängig vom SMC-Layout).
    public var systemChargeLimit: Int? = nil
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
