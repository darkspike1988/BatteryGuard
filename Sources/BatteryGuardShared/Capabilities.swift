import Foundation

/// Was dieser Mac für die Ladesteuerung anbietet. Brüche kommen mit Firmware-Updates,
/// deshalb merkt sich der Dienst den letzten Stand und meldet Änderungen.
public struct BGCapabilities: Codable, Equatable, Sendable {
    public var firmwareVersion: String?
    public var macOSVersion: String?
    public var chargeLockKeys: [String]
    public var adapterSwitchKeys: [String]
    public var magSafeLED: Bool
    public var systemChargeLimits: [Int]
    public var highPowerMode: Bool

    public init(firmwareVersion: String?, macOSVersion: String?, chargeLockKeys: [String],
                adapterSwitchKeys: [String], magSafeLED: Bool, systemChargeLimits: [Int], highPowerMode: Bool) {
        self.firmwareVersion = firmwareVersion
        self.macOSVersion = macOSVersion
        self.chargeLockKeys = chargeLockKeys.sorted()
        self.adapterSwitchKeys = adapterSwitchKeys.sorted()
        self.magSafeLED = magSafeLED
        self.systemChargeLimits = systemChargeLimits.sorted()
        self.highPowerMode = highPowerMode
    }

    public init(smcKeys: [String], firmwareVersion: String?, macOSVersion: String?,
                systemChargeLimits: [Int], highPowerMode: Bool) {
        self.init(firmwareVersion: firmwareVersion, macOSVersion: macOSVersion,
                  chargeLockKeys: smcKeys.filter { ["CHTE", "CH0B", "CH0C"].contains($0) },
                  adapterSwitchKeys: smcKeys.filter { ["CHIE", "CH0J", "CH0I"].contains($0) },
                  magSafeLED: smcKeys.contains("ACLC"),
                  systemChargeLimits: systemChargeLimits, highPowerMode: highPowerMode)
    }

    /// Lesbare Unterschiede für Log und Mitteilung; leer, wenn nichts Relevantes geändert wurde.
    public func changes(since previous: BGCapabilities) -> [String] {
        var result: [String] = []
        if firmwareVersion != previous.firmwareVersion {
            result.append("Firmware \(previous.firmwareVersion ?? "?") → \(firmwareVersion ?? "?")")
        }
        if chargeLockKeys != previous.chargeLockKeys {
            result.append(chargeLockKeys.isEmpty ? "SMC-Ladesperre nicht mehr verfügbar" : "SMC-Ladesperre verfügbar")
        }
        if adapterSwitchKeys != previous.adapterSwitchKeys {
            result.append(adapterSwitchKeys.isEmpty ? "Netzteil-Schalter nicht mehr verfügbar" : "Netzteil-Schalter verfügbar")
        }
        if systemChargeLimits != previous.systemChargeLimits {
            result.append(systemChargeLimits.isEmpty ? "macOS-Limit nicht mehr verfügbar" : "macOS-Limit verfügbar")
        }
        if magSafeLED != previous.magSafeLED { result.append(magSafeLED ? "MagSafe-LED verfügbar" : "MagSafe-LED nicht mehr verfügbar") }
        if highPowerMode != previous.highPowerMode { result.append(highPowerMode ? "High Power Mode verfügbar" : "High Power Mode nicht mehr verfügbar") }
        return result
    }
}

/// Zuletzt beobachtete Änderung der Fähigkeiten (im Status, damit die App einmalig melden kann).
public struct BGCapabilityChange: Codable, Equatable, Sendable {
    public var detectedAt: Date
    public var changes: [String]

    public init(detectedAt: Date, changes: [String]) {
        self.detectedAt = detectedAt
        self.changes = changes
    }
}
