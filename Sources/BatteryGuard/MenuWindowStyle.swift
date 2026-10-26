import Foundation

/// Voreinstellungen für die Karten im Menüfenster (Minimal, Gesundheit, Profi).
enum MenuWindowStyle: String, CaseIterable, Identifiable {
    case minimal, health, powerUser
    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: L("Minimal: Status und Energiefluss")
        case .health: L("Gesundheit: Kapazität, Temperatur, Verlauf")
        case .powerUser: L("Profi: alle Karten")
        }
    }

    /// Kartenschalter, die der Stil setzt; die Reihenfolge der Karten bleibt unverändert.
    var cards: [String: Bool] {
        let keys = MenuBarAppearanceKeys.self
        switch self {
        case .minimal:
            return [keys.showTemperature: false, keys.showPower: false, keys.showHealth: false,
                    keys.showPowerFlow: true, keys.showHistory: false, keys.showNextTask: false, keys.menuCardsCompact: true]
        case .health:
            return [keys.showTemperature: true, keys.showPower: false, keys.showHealth: true,
                    keys.showPowerFlow: false, keys.showHistory: true, keys.showNextTask: false, keys.menuCardsCompact: false]
        case .powerUser:
            return [keys.showTemperature: true, keys.showPower: true, keys.showHealth: true,
                    keys.showPowerFlow: true, keys.showHistory: true, keys.showNextTask: true, keys.menuCardsCompact: true]
        }
    }

    func apply(to defaults: UserDefaults = .standard) {
        cards.forEach { defaults.set($0.value, forKey: $0.key) }
    }
}
