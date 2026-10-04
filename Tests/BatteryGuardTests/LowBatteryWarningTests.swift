import Testing
import Foundation
@testable import BatteryGuard

@Suite("LowBatteryWarningTests")
struct LowBatteryWarningTests {
    @Test("Prüft Standardwerte (Defaults) und Schlüssel")
    func testDefaults() {
        #expect(LowBatteryWarningPolicy.defaultThreshold == 20)
        #expect(LowBatteryWarningPolicy.validRange == 5...50)
        #expect(LowBatteryWarningPolicy.minThreshold == 5)
        #expect(LowBatteryWarningPolicy.maxThreshold == 50)
        #expect(LowBatteryWarningPolicy.hysteresis == 2)
        #expect(LowBatteryWarningPolicy.userDefaultsKey == "bg.lowBatteryThreshold")

        let suiteName = "test-defaults-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        #expect(LowBatteryWarningPolicy.threshold(from: testDefaults) == 20)
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Prüft Begrenzung (Clamp) auf den gültigen Bereich 5...50 %")
    func testClamp() {
        // Unterhalb des Minimums
        #expect(LowBatteryWarningPolicy.clampThreshold(-10) == 5)
        #expect(LowBatteryWarningPolicy.clampThreshold(0) == 5)
        #expect(LowBatteryWarningPolicy.clampThreshold(4) == 5)

        // Exakte Bereichsgrenzen
        #expect(LowBatteryWarningPolicy.clampThreshold(5) == 5)
        #expect(LowBatteryWarningPolicy.clampThreshold(50) == 50)

        // Gültige Zwischenwerte
        #expect(LowBatteryWarningPolicy.clampThreshold(20) == 20)
        #expect(LowBatteryWarningPolicy.clampThreshold(35) == 35)

        // Oberhalb des Maximums
        #expect(LowBatteryWarningPolicy.clampThreshold(51) == 50)
        #expect(LowBatteryWarningPolicy.clampThreshold(100) == 50)

        // UserDefaults mit Clamp
        let suiteName = "test-clamp-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        testDefaults.set(2, forKey: LowBatteryWarningPolicy.userDefaultsKey)
        #expect(LowBatteryWarningPolicy.threshold(from: testDefaults) == 5)

        testDefaults.set(30, forKey: LowBatteryWarningPolicy.userDefaultsKey)
        #expect(LowBatteryWarningPolicy.threshold(from: testDefaults) == 30)

        testDefaults.set(99, forKey: LowBatteryWarningPolicy.userDefaultsKey)
        #expect(LowBatteryWarningPolicy.threshold(from: testDefaults) == 50)

        testDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Prüft Unterscheidung zwischen Akkubetrieb und Netzteil")
    func testPowerSourceBehavior() {
        var policy = LowBatteryWarningPolicy()

        // Am Netzteil (onBattery == false): Keine Warnung, selbst bei niedrigem Akkustand
        let evaluation1 = !policy.evaluate(percent: 10, onBattery: false, threshold: 20)
        #expect(evaluation1)
        #expect(!policy.didWarn)

        // Wechsel auf Akkubetrieb: Warnung wird ausgelöst
        let evaluation2 = policy.evaluate(percent: 10, onBattery: true, threshold: 20)
        #expect(evaluation2)
        #expect(policy.didWarn)

        // Netzteil wieder angeschlossen: Warnstatus wird zurückgesetzt
        let evaluation3 = !policy.evaluate(percent: 10, onBattery: false, threshold: 20)
        #expect(evaluation3)
        #expect(!policy.didWarn)

        // Netzteil erneut getrennt (weiterhin unter Schwelle): Warnung löst erneut aus
        let evaluation4 = policy.evaluate(percent: 10, onBattery: true, threshold: 20)
        #expect(evaluation4)
        #expect(policy.didWarn)
    }

    @Test("Prüft Einmalwarnung (keine wiederholten Benachrichtigungen bei fallendem/gleichem Stand)")
    func testSingleWarning() {
        var policy = LowBatteryWarningPolicy()

        // Über der Schwelle: keine Warnung
        let evaluation5 = !policy.evaluate(percent: 25, onBattery: true, threshold: 20)
        #expect(evaluation5)
        #expect(!policy.didWarn)

        // Erreicht die Schwelle (20 %): löst genau einmal aus
        let evaluation6 = policy.evaluate(percent: 20, onBattery: true, threshold: 20)
        #expect(evaluation6)
        #expect(policy.didWarn)

        // Zweiter Aufruf bei 20 %: keine erneute Warnung
        let evaluation7 = !policy.evaluate(percent: 20, onBattery: true, threshold: 20)
        #expect(evaluation7)
        #expect(policy.didWarn)

        // Weiteres Absinken: keine erneute Warnung
        let evaluation8 = !policy.evaluate(percent: 19, onBattery: true, threshold: 20)
        #expect(evaluation8)
        let evaluation9 = !policy.evaluate(percent: 15, onBattery: true, threshold: 20)
        #expect(evaluation9)
        let evaluation10 = !policy.evaluate(percent: 5, onBattery: true, threshold: 20)
        #expect(evaluation10)
        #expect(policy.didWarn)

        // Deaktiviert (enabled == false): keine Warnung, kein didWarn
        var disabledPolicy = LowBatteryWarningPolicy()
        let evaluation11 = !disabledPolicy.evaluate(percent: 10, onBattery: true, threshold: 20, enabled: false)
        #expect(evaluation11)
        #expect(!disabledPolicy.didWarn)
    }

    @Test("Prüft 2%-Hysterese bei der Rücksetzung der Warnung")
    func testHysteresis() {
        var policy = LowBatteryWarningPolicy()
        let threshold = 20

        // Warnung bei 18 % auslösen
        let evaluation12 = policy.evaluate(percent: 18, onBattery: true, threshold: threshold)
        #expect(evaluation12)
        #expect(policy.didWarn)

        // Akkustand steigt auf Schwelle (20 %): noch keine Rücksetzung
        let evaluation13 = !policy.evaluate(percent: 20, onBattery: true, threshold: threshold)
        #expect(evaluation13)
        #expect(policy.didWarn)

        // Akkustand steigt auf Schwelle + 1 (21 %): innerhalb Hysterese, keine Rücksetzung
        let evaluation14 = !policy.evaluate(percent: 21, onBattery: true, threshold: threshold)
        #expect(evaluation14)
        #expect(policy.didWarn)

        // Akkustand steigt auf Schwelle + 2 (22 %): Obergrenze der 2%-Hysterese, noch keine Rücksetzung
        let evaluation15 = !policy.evaluate(percent: 22, onBattery: true, threshold: threshold)
        #expect(evaluation15)
        #expect(policy.didWarn)

        // Akkustand steigt über Schwelle + 2 (23 %): Rücksetzung erfolgt
        let evaluation16 = !policy.evaluate(percent: 23, onBattery: true, threshold: threshold)
        #expect(evaluation16)
        #expect(!policy.didWarn)

        // Fällt danach wieder auf Schwelle: Neue Warnung wird ausgelöst
        let evaluation17 = policy.evaluate(percent: 20, onBattery: true, threshold: threshold)
        #expect(evaluation17)
        #expect(policy.didWarn)
    }
}
