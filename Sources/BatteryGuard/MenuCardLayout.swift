import Foundation

/// Unterstützte Karten im Menüleisten-Fenster von B-Guard.
public enum MenuCardType: String, CaseIterable, Identifiable, Sendable {
    case metrics = "metrics"
    case powerFlow = "powerFlow"
    case history = "history"
    case nextTask = "nextTask"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .metrics:
            return "Metriken"
        case .powerFlow:
            return "Energiefluss"
        case .history:
            return "Verlauf"
        case .nextTask: return "Nächste Aufgabe"
        }
    }

    public var displayName: String { title }
}

/// Schlüssel für die Menükarten-Konfiguration.
public enum MenuCardLayoutKeys {
    public static let order = "bg.menuCardOrder"
    public static let showHistory = "bg.menuShowHistory"
    public static let compact = "bg.menuCardsCompact"
}

/// Reines Modell und Validierungslogik für konfigurierbare Menükarten.
public enum MenuCardLayout {
    public static let defaultOrder: [MenuCardType] = [.metrics, .powerFlow, .history, .nextTask]
    public static let defaultRawOrder: String = defaultOrder.map(\.rawValue).joined(separator: ",")
    public static let defaultShowHistory: Bool = false
    public static let defaultCompact: Bool = false

    /// Validiert die gespeicherte Reihenfolge:
    /// - Filtert ungültige oder unbekannte Einträge heraus
    /// - Entfernt Duplikate unter Beibehaltung der ersten Position
    /// - Fügt fehlende unterstützte Karten in Standardreihenfolge hinzu
    /// - Liefert bei leerem oder korruptem String die Standardreihenfolge
    /// - Garantiert, dass jede unterstützte Karte genau einmal vorkommt
    public static func validate(rawOrder: String?) -> [MenuCardType] {
        guard let rawOrder, !rawOrder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultOrder
        }

        var seen = Set<MenuCardType>()
        var result: [MenuCardType] = []

        let tokens = rawOrder.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for token in tokens {
            if let card = MenuCardType(rawValue: token) {
                if !seen.contains(card) {
                    seen.insert(card)
                    result.append(card)
                }
            }
        }

        for card in defaultOrder {
            if !seen.contains(card) {
                seen.insert(card)
                result.append(card)
            }
        }

        return result
    }

    /// Serialisiert eine Liste von Karten in einen kommagetrennten String.
    public static func serialize(_ cards: [MenuCardType]) -> String {
        cards.map(\.rawValue).joined(separator: ",")
    }

    /// Begrenztes Nach-Oben-Verschieben (bounded move up).
    /// Steht das Element bereits ganz oben (Index 0), bleibt die Reihenfolge unverändert.
    public static func moveUp(card: MenuCardType, in order: [MenuCardType]) -> [MenuCardType] {
        var validated = validate(rawOrder: serialize(order))
        guard let index = validated.firstIndex(of: card), index > 0 else {
            return validated
        }
        validated.swapAt(index, index - 1)
        return validated
    }

    /// Begrenztes Nach-Unten-Verschieben (bounded move down).
    /// Steht das Element bereits ganz unten (letzter Index), bleibt die Reihenfolge unverändert.
    public static func moveDown(card: MenuCardType, in order: [MenuCardType]) -> [MenuCardType] {
        var validated = validate(rawOrder: serialize(order))
        guard let index = validated.firstIndex(of: card), index < validated.count - 1 else {
            return validated
        }
        validated.swapAt(index, index + 1)
        return validated
    }

    /// Prüft, ob ein Element nach oben bewegt werden kann.
    public static func canMoveUp(card: MenuCardType, in order: [MenuCardType]) -> Bool {
        let validated = validate(rawOrder: serialize(order))
        guard let index = validated.firstIndex(of: card) else { return false }
        return index > 0
    }

    /// Prüft, ob ein Element nach unten bewegt werden kann.
    public static func canMoveDown(card: MenuCardType, in order: [MenuCardType]) -> Bool {
        let validated = validate(rawOrder: serialize(order))
        guard let index = validated.firstIndex(of: card) else { return false }
        return index < validated.count - 1
    }

    // MARK: - String-basierte Hilfsmethoden für AppStorage

    public static func moveUp(card: MenuCardType, in rawOrder: String) -> String {
        let current = validate(rawOrder: rawOrder)
        let moved = moveUp(card: card, in: current)
        return serialize(moved)
    }

    public static func moveDown(card: MenuCardType, in rawOrder: String) -> String {
        let current = validate(rawOrder: rawOrder)
        let moved = moveDown(card: card, in: current)
        return serialize(moved)
    }

    public static func canMoveUp(card: MenuCardType, in rawOrder: String) -> Bool {
        canMoveUp(card: card, in: validate(rawOrder: rawOrder))
    }

    public static func canMoveDown(card: MenuCardType, in rawOrder: String) -> Bool {
        canMoveDown(card: card, in: validate(rawOrder: rawOrder))
    }
}
