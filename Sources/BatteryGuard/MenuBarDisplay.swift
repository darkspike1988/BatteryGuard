import Foundation
import BatteryGuardShared

/// Auswahl für die Anzeige in der Menüleiste neben dem Ladering.
public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconOnly = "iconOnly"
    case percent = "percent"
    case temperature = "temperature"
    case power = "power"
    case percentAndTemperature = "percentAndTemperature"
    case percentAndPower = "percentAndPower"

    public static let appStorageKey = "bg.menuBarDisplay"
    public static let defaultMode: MenuBarDisplayMode = .percent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconOnly:
            return "Symbol allein"
        case .percent:
            return "Prozent"
        case .temperature:
            return "Akkutemperatur"
        case .power:
            return "Akku-Leistung"
        case .percentAndTemperature:
            return "Prozent & Akkutemperatur"
        case .percentAndPower:
            return "Prozent & Akku-Leistung"
        }
    }

    public init(fromRawString string: String?) {
        guard let string else {
            self = .percent
            return
        }
        switch string.lowercased() {
        case "icononly", "symbol", "icon", "symbolallein", "symbol allein":
            self = .iconOnly
        case "percent", "prozent", "percentage":
            self = .percent
        case "temperature", "akkutemperatur", "temp":
            self = .temperature
        case "power", "akku-leistung", "akkuleistung", "leistung", "watts":
            self = .power
        case "percentandtemperature", "percent_and_temperature", "percenttemperature",
             "percentandtemp", "percent & temperature", "percent&temperature",
             "percent & temp", "percent&temp", "percent+temperature", "percent+temp",
             "prozent & akkutemperatur", "prozent&akkutemperatur",
             "prozent und akkutemperatur", "prozent & temperatur",
             "prozent&temperatur", "prozent und temperatur",
             "prozentakkutemperatur", "prozenttemperatur",
             "prozent-temperatur", "prozent-akkutemperatur",
             "prozent & temp", "prozent&temp":
            self = .percentAndTemperature
        case "percentandpower", "percent_and_power", "percentpower",
             "percent & power", "percent&power", "percent+power",
             "percentandwatts", "percent & watts", "percent&watts",
             "prozent & akku-leistung", "prozent&akku-leistung",
             "prozent & akkuleistung", "prozent&akkuleistung",
             "prozent & leistung", "prozent&leistung",
             "prozent und akku-leistung", "prozent und akkuleistung",
             "prozent und leistung", "prozentakku-leistung",
             "prozentakkuleistung", "prozentleistung",
             "prozent-leistung", "prozent-akku-leistung",
             "prozent & watts", "prozent&watts":
            self = .percentAndPower
        default:
            self = .percent
        }
    }
}

public typealias MenuBarDisplay = MenuBarDisplayMode

/// Formatierungs- und Logikfunktionen für die Menüleistenanzeige.
public struct MenuBarDisplayFormatter {
    public static let dash = "–"
    public static let powerNotice = "Akku-Leistung ist Lade-/Entladefluss, nicht gesamte Mac-Leistung"

    /// Prozentwert auf den Bereich 0...100 begrenzen.
    public static func clampPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(), 0), 100))
    }

    public static func clampPercent(_ value: Int) -> Int {
        return min(max(value, 0), 100)
    }

    /// Prozentanzeige formatieren: 0...100 %, bei Inaktivität/Fehlen Gedankenstrich.
    public static func formatPercent(_ value: Double?, isDaemonActive: Bool = true) -> String {
        guard isDaemonActive, let value, value.isFinite else {
            return "\(dash) %"
        }
        return "\(clampPercent(value)) %"
    }

    public static func formatPercent(_ value: Int?, isDaemonActive: Bool = true) -> String {
        guard isDaemonActive, let value else {
            return "\(dash) %"
        }
        return "\(clampPercent(value)) %"
    }

    /// Temperatur formatieren: ein Nachkomma °C, bei Inaktivität/Fehlen Gedankenstrich.
    public static func formatTemperature(_ celsius: Double?, isDaemonActive: Bool = true) -> String {
        guard isDaemonActive, let celsius, celsius.isFinite else {
            return "\(dash) °C"
        }
        let normalized = celsius
        return String(format: "%.1f °C", normalized)
    }

    /// Leistung formatieren: ein Nachkomma W signed (+/-), bei Inaktivität/Fehlen Gedankenstrich.
    public static func formatPower(_ watts: Double?, isDaemonActive: Bool = true) -> String {
        guard isDaemonActive, let watts, watts.isFinite else {
            return "\(dash) W"
        }
        let normalized = watts
        let safeWatts = abs(normalized) < 0.05 ? 0.0 : normalized
        return String(format: "%+.1f W", safeWatts)
    }

    /// Textanzeige für die Menüleiste erzeugen.
    public static func text(for mode: MenuBarDisplayMode,
                            percent: Int?,
                            temperature: Double?,
                            power: Double?,
                            isDaemonActive: Bool) -> String {
        switch mode {
        case .iconOnly:
            return ""
        case .percent:
            return formatPercent(percent, isDaemonActive: isDaemonActive)
        case .temperature:
            return formatTemperature(temperature, isDaemonActive: isDaemonActive)
        case .power:
            return formatPower(power, isDaemonActive: isDaemonActive)
        case .percentAndTemperature:
            let pStr = formatPercent(percent, isDaemonActive: isDaemonActive)
            let tStr = formatTemperature(temperature, isDaemonActive: isDaemonActive)
            return "\(pStr) \(tStr)"
        case .percentAndPower:
            let pStr = formatPercent(percent, isDaemonActive: isDaemonActive)
            let wStr = formatPower(power, isDaemonActive: isDaemonActive)
            return "\(pStr) \(wStr)"
        }
    }

    /// Textanzeige für die Menüleiste basierend auf BGStatus erzeugen.
    public static func text(for mode: MenuBarDisplayMode,
                            status: BGStatus,
                            isDaemonActive: Bool) -> String {
        let temp = extractTemperature(from: status)
        let power = extractPower(from: status)
        return text(for: mode,
                    percent: status.hasBatteryPercent ? status.percent : nil,
                    temperature: temp,
                    power: power,
                    isDaemonActive: isDaemonActive)
    }

    /// Tooltip mit Hinweistext erzeugen.
    public static func tooltip(for mode: MenuBarDisplayMode,
                               percent: Int?,
                               temperature: Double?,
                               power: Double?,
                               isDaemonActive: Bool) -> String {
        guard isDaemonActive else {
            if mode == .power || mode == .percentAndPower {
                return "B-Guard · Dienst nicht aktiv. \(powerNotice)."
            }
            return "B-Guard · Hintergrunddienst nicht aktiv"
        }
        switch mode {
        case .iconOnly:
            return "B-Guard · Akkustand: \(formatPercent(percent, isDaemonActive: true))"
        case .percent:
            return "B-Guard · Akkustand: \(formatPercent(percent, isDaemonActive: true))"
        case .temperature:
            return "B-Guard · Akkutemperatur: \(formatTemperature(temperature, isDaemonActive: true))"
        case .power:
            let pStr = formatPower(power, isDaemonActive: true)
            return "B-Guard · Akku-Leistung: \(pStr). \(powerNotice)."
        case .percentAndTemperature:
            let pStr = formatPercent(percent, isDaemonActive: true)
            let tStr = formatTemperature(temperature, isDaemonActive: true)
            return "B-Guard · Akkustand: \(pStr), Akkutemperatur: \(tStr)"
        case .percentAndPower:
            let pStr = formatPercent(percent, isDaemonActive: true)
            let wStr = formatPower(power, isDaemonActive: true)
            return "B-Guard · Akkustand: \(pStr), Akku-Leistung: \(wStr). \(powerNotice)."
        }
    }

    public static func tooltip(for mode: MenuBarDisplayMode,
                               status: BGStatus,
                               isDaemonActive: Bool) -> String {
        let temp = extractTemperature(from: status)
        let power = extractPower(from: status)
        return tooltip(for: mode,
                       percent: status.hasBatteryPercent ? status.percent : nil,
                       temperature: temp,
                       power: power,
                       isDaemonActive: isDaemonActive)
    }

    /// Barrierefreier VoiceOver-Zusammenfassungstext.
    public static func voiceOverText(for mode: MenuBarDisplayMode,
                                     percent: Int?,
                                     temperature: Double?,
                                     power: Double?,
                                     isDaemonActive: Bool) -> String {
        guard isDaemonActive else {
            if mode == .power || mode == .percentAndPower {
                return "B-Guard: Hintergrunddienst nicht aktiv. \(powerNotice)."
            }
            return "B-Guard: Hintergrunddienst nicht aktiv"
        }
        switch mode {
        case .iconOnly:
            return "B-Guard, Akkustand \(formatPercent(percent, isDaemonActive: true))"
        case .percent:
            return "B-Guard, Akkustand \(formatPercent(percent, isDaemonActive: true))"
        case .temperature:
            return "B-Guard, Akkutemperatur \(formatTemperature(temperature, isDaemonActive: true))"
        case .power:
            let pStr = formatPower(power, isDaemonActive: true)
            return "B-Guard, Akku-Leistung \(pStr). \(powerNotice)."
        case .percentAndTemperature:
            let pStr = formatPercent(percent, isDaemonActive: true)
            let tStr = formatTemperature(temperature, isDaemonActive: true)
            return "B-Guard, Akkustand \(pStr), Akkutemperatur \(tStr)"
        case .percentAndPower:
            let pStr = formatPercent(percent, isDaemonActive: true)
            let wStr = formatPower(power, isDaemonActive: true)
            return "B-Guard, Akkustand \(pStr), Akku-Leistung \(wStr). \(powerNotice)."
        }
    }

    public static func voiceOverText(for mode: MenuBarDisplayMode,
                                     status: BGStatus,
                                     isDaemonActive: Bool) -> String {
        let temp = extractTemperature(from: status)
        let power = extractPower(from: status)
        return voiceOverText(for: mode,
                             percent: status.hasBatteryPercent ? status.percent : nil,
                             temperature: temp,
                             power: power,
                             isDaemonActive: isDaemonActive)
    }

    public static func extractTemperature(from status: BGStatus) -> Double? {
        status.temperatureCelsius
    }

    public static func extractPower(from status: BGStatus) -> Double? {
        status.watts
    }
}
