import Foundation

/// Gemeinsamer Vertrag zwischen Menüleisten-App (User) und Daemon (root).
/// Kommunikation läuft über zwei JSON-Dateien – kein XPC/Signing nötig.
public enum BGPaths {
    public static let directory = "/Library/Application Support/BatteryGuard"
    /// Von der App geschrieben (0666), vom Daemon gelesen + validiert.
    public static let config = directory + "/config.json"
    /// Vom Daemon geschrieben (0644), von der App gelesen.
    public static let status = directory + "/status.json"
    public static let daemonLabel = "com.batteryguard.daemon"
    public static let daemonPlist = "/Library/LaunchDaemons/com.batteryguard.daemon.plist"
    public static let daemonBinary = "/usr/local/libexec/batteryguardd"
}

/// Wie das Limit durchgesetzt wird.
public enum BGMode: String, Codable, CaseIterable, Sendable {
    /// Daemon wählt selbst: natives macOS-Limit, wenn es zum Maximum passt, sonst Pendel-Modus.
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
        mode = (try? c.decodeIfPresent(BGMode.self, forKey: .mode)) ?? d.mode
    }

    /// Daemon MUSS jede gelesene Config durch diese Funktion schicken (Config-Datei ist world-writable).
    public func sanitized() -> BGConfig {
        var c = self
        c.lowerLimit = min(max(c.lowerLimit, 5), 95)
        c.upperLimit = min(max(c.upperLimit, 20), 100)
        if c.upperLimit <= c.lowerLimit { c.lowerLimit = max(5, c.upperLimit - 5) }
        c.heatProtectionCelsius = (c.heatProtectionCelsius == 0) ? 0 : min(max(c.heatProtectionCelsius, 30), 50)
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
    public var percent: Int = 0
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
    public var smcKeysDetected: [String] = []
    public var daemonVersion: String = "0.1.0"
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
