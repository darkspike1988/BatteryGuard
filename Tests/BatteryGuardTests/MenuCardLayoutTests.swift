import Foundation
import Testing
@testable import BatteryGuard

@Suite("MenuCardLayoutTests")
struct MenuCardLayoutTests {

    @Test("Standardreihenfolge und Serialisierung")
    func testDefaultOrderAndSerialization() {
        #expect(MenuCardLayout.defaultOrder == [.metrics, .powerFlow, .history, .nextTask])
        #expect(MenuCardLayout.defaultRawOrder == "metrics,powerFlow,history,nextTask")
        #expect(MenuCardLayout.defaultShowHistory == false)
        #expect(MenuCardLayout.defaultCompact == false)

        let serialized = MenuCardLayout.serialize([.history, .powerFlow, .metrics])
        #expect(serialized == "history,powerFlow,metrics")

        #expect(MenuCardType.metrics.displayName == "Metriken")
        #expect(MenuCardType.powerFlow.displayName == "Energiefluss")
        #expect(MenuCardType.history.displayName == "Verlauf")
    }

    @Test("Validierung behandelt korrupte und leere Eingaben")
    func testValidationCorruptedInput() {
        // nil und leere Strings liefern Standardreihenfolge
        #expect(MenuCardLayout.validate(rawOrder: nil) == MenuCardLayout.defaultOrder)
        #expect(MenuCardLayout.validate(rawOrder: "") == MenuCardLayout.defaultOrder)
        #expect(MenuCardLayout.validate(rawOrder: "   ") == MenuCardLayout.defaultOrder)

        // Beliebige korrupte oder unbekannte Strings liefern Standardreihenfolge
        #expect(MenuCardLayout.validate(rawOrder: "unknown,corrupted,%%%") == MenuCardLayout.defaultOrder)
        #expect(MenuCardLayout.validate(rawOrder: ",,,,") == MenuCardLayout.defaultOrder)
        #expect(MenuCardLayout.validate(rawOrder: "  invalid  ") == MenuCardLayout.defaultOrder)
    }

    @Test("Validierung entfernt Duplikate und behält alle unterstützten Karten genau einmal")
    func testValidationDuplicates() {
        // Duplikate werden entfernt, erste Position bleibt erhalten, fehlende werden angehängt
        let dup1 = MenuCardLayout.validate(rawOrder: "metrics,metrics,powerFlow")
        #expect(dup1 == [.metrics, .powerFlow, .history, .nextTask])

        let dup2 = MenuCardLayout.validate(rawOrder: "history,powerFlow,history,metrics,history")
        #expect(dup2 == [.history, .powerFlow, .metrics, .nextTask])

        let dup3 = MenuCardLayout.validate(rawOrder: "powerFlow,powerFlow,powerFlow")
        #expect(dup3 == [.powerFlow, .metrics, .history, .nextTask])
    }

    @Test("Validierung filtert unbekannte Einträge und ergänzt fehlende Karten")
    func testValidationUnknownAndMissing() {
        let partial1 = MenuCardLayout.validate(rawOrder: "history")
        #expect(partial1 == [.history, .metrics, .powerFlow, .nextTask])

        let partial2 = MenuCardLayout.validate(rawOrder: "powerFlow,garbageToken,history")
        #expect(partial2 == [.powerFlow, .history, .metrics, .nextTask])

        let whitespace = MenuCardLayout.validate(rawOrder: "  powerFlow  ,  history  ")
        #expect(whitespace == [.powerFlow, .history, .metrics, .nextTask])
    }

    @Test("Begrenztes Nach-Oben-Verschieben (bounded move up)")
    func testBoundedMoveUp() {
        let initial = MenuCardLayout.defaultOrder // [.metrics, .powerFlow, .history]

        // Element am oberen Rand kann nicht weiter nach oben verschoben werden
        #expect(MenuCardLayout.canMoveUp(card: .metrics, in: initial) == false)
        #expect(MenuCardLayout.moveUp(card: .metrics, in: initial) == initial)

        // Mittleres Element verschiebt sich an Position 0
        #expect(MenuCardLayout.canMoveUp(card: .powerFlow, in: initial) == true)
        let movedMiddle = MenuCardLayout.moveUp(card: .powerFlow, in: initial)
        #expect(movedMiddle == [.powerFlow, .metrics, .history, .nextTask])

        // Unteres Element verschiebt sich an Position 1
        #expect(MenuCardLayout.canMoveUp(card: .history, in: initial) == true)
        let movedBottom = MenuCardLayout.moveUp(card: .history, in: initial)
        #expect(movedBottom == [.metrics, .history, .powerFlow, .nextTask])

        // String-basierte Hilfsmethode
        let rawMoved = MenuCardLayout.moveUp(card: .history, in: "metrics,powerFlow,history")
        #expect(rawMoved == "metrics,history,powerFlow,nextTask")

        let rawBound = MenuCardLayout.moveUp(card: .metrics, in: "metrics,powerFlow,history")
        #expect(rawBound == "metrics,powerFlow,history,nextTask")
    }

    @Test("Begrenztes Nach-Unten-Verschieben (bounded move down)")
    func testBoundedMoveDown() {
        let initial = MenuCardLayout.defaultOrder // [.metrics, .powerFlow, .history]

        // Element am unteren Rand kann nicht weiter nach unten verschoben werden
        #expect(MenuCardLayout.canMoveDown(card: .nextTask, in: initial) == false)
        #expect(MenuCardLayout.moveDown(card: .nextTask, in: initial) == initial)

        // Mittleres Element verschiebt sich an Position 2
        #expect(MenuCardLayout.canMoveDown(card: .powerFlow, in: initial) == true)
        let movedMiddle = MenuCardLayout.moveDown(card: .powerFlow, in: initial)
        #expect(movedMiddle == [.metrics, .history, .powerFlow, .nextTask])

        // Oberes Element verschiebt sich an Position 1
        #expect(MenuCardLayout.canMoveDown(card: .metrics, in: initial) == true)
        let movedTop = MenuCardLayout.moveDown(card: .metrics, in: initial)
        #expect(movedTop == [.powerFlow, .metrics, .history, .nextTask])

        // String-basierte Hilfsmethode
        let rawMoved = MenuCardLayout.moveDown(card: .metrics, in: "metrics,powerFlow,history")
        #expect(rawMoved == "powerFlow,metrics,history,nextTask")

        let rawBound = MenuCardLayout.moveDown(card: .nextTask, in: "metrics,powerFlow,history")
        #expect(rawBound == "metrics,powerFlow,history,nextTask")
    }

    @Test("Reset-Helper setzt Darstellung inklusive Reihenfolge, Kompakt und Verlauf zurück und erhält fremde Einstellungen")
    func testResetPreservesUnrelatedPrefsIsolatedSuite() {
        let suiteName = "BGuardTestMenuCardLayout.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults-Suite konnte nicht erstellt werden")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        // 1. Fremde Einstellungen setzen
        defaults.set(true, forKey: "bg.notifyLow")
        defaults.set(18, forKey: "bg.lowBatteryThreshold")
        defaults.set("native", forKey: "bg.chargeMode")
        defaults.set(75, forKey: "bg.chargeUpperLimit")
        defaults.set(true, forKey: "bg.launchAtLogin")
        defaults.set("secureLocalToken123", forKey: "bg.localApiKey")
        defaults.set("preserve-me", forKey: "unrelated.custom.key")

        // 2. Benutzerdefinierte Darstellungswerte setzen
        defaults.set("battery", forKey: MenuBarAppearanceKeys.iconStyle)
        defaults.set("watt", forKey: MenuBarAppearanceKeys.displayMode)
        defaults.set(true, forKey: MenuBarAppearanceKeys.showTemperature)
        defaults.set(true, forKey: MenuBarAppearanceKeys.showPower)
        defaults.set(true, forKey: MenuBarAppearanceKeys.showHealth)
        defaults.set(true, forKey: MenuBarAppearanceKeys.showPowerFlow)
        defaults.set("history,powerFlow,metrics", forKey: MenuBarAppearanceKeys.menuCardOrder)
        defaults.set(true, forKey: MenuBarAppearanceKeys.showHistory)
        defaults.set(true, forKey: MenuBarAppearanceKeys.menuCardsCompact)

        // 3. Reset ausführen
        MenuBarAppearance.resetDisplayPreferences(userDefaults: defaults)

        // 4. Zurückgesetzte Werte prüfen (inklusive der neuen Schlüssel)
        #expect(defaults.string(forKey: MenuBarAppearanceKeys.iconStyle) == "ring")
        #expect(defaults.string(forKey: MenuBarAppearanceKeys.displayMode) == "percent")
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showTemperature) == false)
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showPower) == false)
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showHealth) == false)
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showPowerFlow) == false)
        #expect(defaults.string(forKey: MenuBarAppearanceKeys.menuCardOrder) == "metrics,powerFlow,history,nextTask")
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showHistory) == false)
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.menuCardsCompact) == false)

        // 5. Erhalt aller fremden/nicht-darstellungsbezogenen Einstellungen verifizieren
        #expect(defaults.bool(forKey: "bg.notifyLow") == true)
        #expect(defaults.integer(forKey: "bg.lowBatteryThreshold") == 18)
        #expect(defaults.string(forKey: "bg.chargeMode") == "native")
        #expect(defaults.integer(forKey: "bg.chargeUpperLimit") == 75)
        #expect(defaults.bool(forKey: "bg.launchAtLogin") == true)
        #expect(defaults.string(forKey: "bg.localApiKey") == "secureLocalToken123")
        #expect(defaults.string(forKey: "unrelated.custom.key") == "preserve-me")
    }
}
