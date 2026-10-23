import Foundation
import BatteryGuardShared

/// Zusätzliche, einzeln zuschaltbare Werte hinter der Menüleistenanzeige.
public enum MenuBarExtraItem: String, CaseIterable, Identifiable, Sendable {
    case timeRemaining
    case chargeLimit
    case socPower
    case lowPowerMode

    public static let appStorageKey = "bg.menuBarExtras"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .timeRemaining: "Restlaufzeit"
        case .chargeLimit: "Wirksames Ladeziel"
        case .socPower: "SoC-Leistung"
        case .lowPowerMode: "Low-Power-Symbol"
        }
    }
    public var localizedTitle: String { L(title) }

    /// Gespeicherte Auswahl als kommagetrennte Liste; unbekannte Einträge werden ignoriert.
    public static func decode(_ raw: String) -> [MenuBarExtraItem] {
        let selected = Set(raw.split(separator: ",").compactMap { MenuBarExtraItem(rawValue: String($0)) })
        return allCases.filter(selected.contains)
    }

    public static func encode(_ items: [MenuBarExtraItem]) -> String {
        allCases.filter(items.contains).map(\.rawValue).joined(separator: ",")
    }

    public static func toggled(_ item: MenuBarExtraItem, in raw: String) -> String {
        var items = decode(raw)
        if let index = items.firstIndex(of: item) { items.remove(at: index) } else { items.append(item) }
        return encode(items)
    }
}

public enum MenuBarExtraFormatter {
    /// Textteile für die Menüleiste; fehlende oder veraltete Werte entfallen statt Platzhalter zu zeigen.
    public static func texts(for items: [MenuBarExtraItem], status: BGStatus, isDaemonActive: Bool,
                             now: Date = Date()) -> [String] {
        guard isDaemonActive else { return [] }
        return items.compactMap { item in
            switch item {
            case .timeRemaining:
                guard let minutes = status.timeRemainingMinutes, minutes > 0, minutes < 100 * 60 else { return nil }
                return String(format: "%d:%02d h", minutes / 60, minutes % 60)
            case .chargeLimit:
                guard let limit = status.effectiveUpperLimit, (1...100).contains(limit) else { return nil }
                return "→\(limit) %"
            case .socPower:
                guard let soc = status.socPower, soc.isFresh(at: now), let watts = soc.socWatts else { return nil }
                return String(format: "SoC %.1f W", watts)
            case .lowPowerMode:
                return nil // Symbol, siehe showsLowPowerSymbol
            }
        }
    }

    public static func showsLowPowerSymbol(for items: [MenuBarExtraItem], lowPowerModeEnabled: Bool) -> Bool {
        items.contains(.lowPowerMode) && lowPowerModeEnabled
    }
}
