import XCTest
@testable import BatteryGuard

final class CombinedMenuDisplayTests: XCTestCase {

    // MARK: - Case Count and Root Handles

    func testCaseCountAndRootHandles() {
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 6)

        let expectedCases: [MenuBarDisplayMode] = [
            .iconOnly,
            .percent,
            .temperature,
            .power,
            .percentAndTemperature,
            .percentAndPower
        ]
        XCTAssertEqual(MenuBarDisplayMode.allCases, expectedCases)

        XCTAssertEqual(MenuBarDisplayMode.defaultMode, .percent)
        XCTAssertEqual(MenuBarDisplayMode.appStorageKey, "bg.menuBarDisplay")

        XCTAssertEqual(MenuBarDisplayMode.percentAndTemperature.rawValue, "percentAndTemperature")
        XCTAssertEqual(MenuBarDisplayMode.percentAndPower.rawValue, "percentAndPower")

        XCTAssertEqual(MenuBarDisplayMode.percentAndTemperature.title, "Prozent & Akkutemperatur")
        XCTAssertEqual(MenuBarDisplayMode.percentAndPower.title, "Prozent & Akku-Leistung")

        for mode in MenuBarDisplayMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
            XCTAssertFalse(mode.title.isEmpty)

            _ = MenuBarDisplayFormatter.text(for: mode, percent: 50, temperature: 25.0, power: 10.0, isDaemonActive: true)
            _ = MenuBarDisplayFormatter.tooltip(for: mode, percent: 50, temperature: 25.0, power: 10.0, isDaemonActive: true)
            _ = MenuBarDisplayFormatter.voiceOverText(for: mode, percent: 50, temperature: 25.0, power: 10.0, isDaemonActive: true)

            _ = MenuBarDisplayFormatter.text(for: mode, percent: nil, temperature: nil, power: nil, isDaemonActive: false)
            _ = MenuBarDisplayFormatter.tooltip(for: mode, percent: nil, temperature: nil, power: nil, isDaemonActive: false)
            _ = MenuBarDisplayFormatter.voiceOverText(for: mode, percent: nil, temperature: nil, power: nil, isDaemonActive: false)
        }
    }

    // MARK: - Parser Roundtrip and Lowercase Recognition

    func testParserRoundtripAndLowercaseRecognition() {
        for mode in MenuBarDisplayMode.allCases {
            XCTAssertEqual(MenuBarDisplayMode(fromRawString: mode.rawValue), mode)
            XCTAssertEqual(MenuBarDisplayMode(fromRawString: mode.rawValue.lowercased()), mode)
            XCTAssertEqual(MenuBarDisplayMode(fromRawString: mode.rawValue.uppercased()), mode)
            XCTAssertEqual(MenuBarDisplayMode(fromRawString: mode.title), mode)
            XCTAssertEqual(MenuBarDisplayMode(fromRawString: mode.title.lowercased()), mode)
        }

        // percentAndTemperature aliases and lowercase
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percentandtemperature"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percent_and_temperature"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percent & temperature"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percent&temp"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percentandtemp"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent & akkutemperatur"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent & temperatur"), .percentAndTemperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent&temp"), .percentAndTemperature)

        // percentAndPower aliases and lowercase
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percentandpower"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percent_and_power"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percent & power"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percentandwatts"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent & akku-leistung"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent & akkuleistung"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent & leistung"), .percentAndPower)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent&leistung"), .percentAndPower)

        // Defaults and fallbacks
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: nil), .percent)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: ""), .percent)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "unknown_value"), .percent)
    }

    // MARK: - Combined Fresh Values

    func testCombinedFreshValues() {
        // Percent and Temperature
        let textTemp = MenuBarDisplayFormatter.text(for: .percentAndTemperature, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: true)
        XCTAssertEqual(textTemp, "85 % 32.4 °C")

        let tipTemp = MenuBarDisplayFormatter.tooltip(for: .percentAndTemperature, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: true)
        XCTAssertEqual(tipTemp, "B-Guard · Akkustand: 85 %, Akkutemperatur: 32.4 °C")

        let voTemp = MenuBarDisplayFormatter.voiceOverText(for: .percentAndTemperature, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: true)
        XCTAssertEqual(voTemp, "B-Guard, Akkustand 85 %, Akkutemperatur 32.4 °C")

        // Percent and Power (negative / discharging)
        let textPowerNeg = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: 75, temperature: 28.0, power: -14.2, isDaemonActive: true)
        XCTAssertEqual(textPowerNeg, "75 % -14.2 W")

        let tipPowerNeg = MenuBarDisplayFormatter.tooltip(for: .percentAndPower, percent: 75, temperature: 28.0, power: -14.2, isDaemonActive: true)
        XCTAssertEqual(tipPowerNeg, "B-Guard · Akkustand: 75 %, Akku-Leistung: -14.2 W. \(MenuBarDisplayFormatter.powerNotice).")

        let voPowerNeg = MenuBarDisplayFormatter.voiceOverText(for: .percentAndPower, percent: 75, temperature: 28.0, power: -14.2, isDaemonActive: true)
        XCTAssertEqual(voPowerNeg, "B-Guard, Akkustand 75 %, Akku-Leistung -14.2 W. \(MenuBarDisplayFormatter.powerNotice).")

        // Percent and Power (positive / charging)
        let textPowerPos = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: 90, temperature: 30.0, power: 25.5, isDaemonActive: true)
        XCTAssertEqual(textPowerPos, "90 % +25.5 W")

        let tipPowerPos = MenuBarDisplayFormatter.tooltip(for: .percentAndPower, percent: 90, temperature: 30.0, power: 25.5, isDaemonActive: true)
        XCTAssertEqual(tipPowerPos, "B-Guard · Akkustand: 90 %, Akku-Leistung: +25.5 W. \(MenuBarDisplayFormatter.powerNotice).")

        let voPowerPos = MenuBarDisplayFormatter.voiceOverText(for: .percentAndPower, percent: 90, temperature: 30.0, power: 25.5, isDaemonActive: true)
        XCTAssertEqual(voPowerPos, "B-Guard, Akkustand 90 %, Akku-Leistung +25.5 W. \(MenuBarDisplayFormatter.powerNotice).")

        // Percent and Power (zero watts explicit signed)
        let textPowerZero = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: 100, temperature: 25.0, power: 0.0, isDaemonActive: true)
        XCTAssertEqual(textPowerZero, "100 % +0.0 W")
    }

    // MARK: - Missing Percent

    func testMissingPercent() {
        // Missing percent in percentAndTemperature
        let textTemp = MenuBarDisplayFormatter.text(for: .percentAndTemperature, percent: nil, temperature: 30.5, power: nil, isDaemonActive: true)
        XCTAssertEqual(textTemp, "– % 30.5 °C")

        let tipTemp = MenuBarDisplayFormatter.tooltip(for: .percentAndTemperature, percent: nil, temperature: 30.5, power: nil, isDaemonActive: true)
        XCTAssertEqual(tipTemp, "B-Guard · Akkustand: – %, Akkutemperatur: 30.5 °C")

        let voTemp = MenuBarDisplayFormatter.voiceOverText(for: .percentAndTemperature, percent: nil, temperature: 30.5, power: nil, isDaemonActive: true)
        XCTAssertEqual(voTemp, "B-Guard, Akkustand – %, Akkutemperatur 30.5 °C")

        // Missing percent in percentAndPower
        let textPower = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: nil, temperature: nil, power: -12.0, isDaemonActive: true)
        XCTAssertEqual(textPower, "– % -12.0 W")

        let tipPower = MenuBarDisplayFormatter.tooltip(for: .percentAndPower, percent: nil, temperature: nil, power: -12.0, isDaemonActive: true)
        XCTAssertEqual(tipPower, "B-Guard · Akkustand: – %, Akku-Leistung: -12.0 W. \(MenuBarDisplayFormatter.powerNotice).")

        let voPower = MenuBarDisplayFormatter.voiceOverText(for: .percentAndPower, percent: nil, temperature: nil, power: -12.0, isDaemonActive: true)
        XCTAssertEqual(voPower, "B-Guard, Akkustand – %, Akku-Leistung -12.0 W. \(MenuBarDisplayFormatter.powerNotice).")
    }

    // MARK: - Missing Temperature

    func testMissingTemperature() {
        let textTemp = MenuBarDisplayFormatter.text(for: .percentAndTemperature, percent: 80, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(textTemp, "80 % – °C")

        let tipTemp = MenuBarDisplayFormatter.tooltip(for: .percentAndTemperature, percent: 80, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(tipTemp, "B-Guard · Akkustand: 80 %, Akkutemperatur: – °C")

        let voTemp = MenuBarDisplayFormatter.voiceOverText(for: .percentAndTemperature, percent: 80, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(voTemp, "B-Guard, Akkustand 80 %, Akkutemperatur – °C")
    }

    // MARK: - Missing Power

    func testMissingPower() {
        let textPower = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: 80, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(textPower, "80 % – W")

        let tipPower = MenuBarDisplayFormatter.tooltip(for: .percentAndPower, percent: 80, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(tipPower, "B-Guard · Akkustand: 80 %, Akku-Leistung: – W. \(MenuBarDisplayFormatter.powerNotice).")

        let voPower = MenuBarDisplayFormatter.voiceOverText(for: .percentAndPower, percent: 80, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(voPower, "B-Guard, Akkustand 80 %, Akku-Leistung – W. \(MenuBarDisplayFormatter.powerNotice).")
    }

    // MARK: - Both Missing (No Fake Zero)

    func testBothMissingNoFakeZero() {
        let textTemp = MenuBarDisplayFormatter.text(for: .percentAndTemperature, percent: nil, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(textTemp, "– % – °C")

        let tipTemp = MenuBarDisplayFormatter.tooltip(for: .percentAndTemperature, percent: nil, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(tipTemp, "B-Guard · Akkustand: – %, Akkutemperatur: – °C")

        let voTemp = MenuBarDisplayFormatter.voiceOverText(for: .percentAndTemperature, percent: nil, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(voTemp, "B-Guard, Akkustand – %, Akkutemperatur – °C")

        let textPower = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: nil, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(textPower, "– % – W")

        let tipPower = MenuBarDisplayFormatter.tooltip(for: .percentAndPower, percent: nil, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(tipPower, "B-Guard · Akkustand: – %, Akku-Leistung: – W. \(MenuBarDisplayFormatter.powerNotice).")

        let voPower = MenuBarDisplayFormatter.voiceOverText(for: .percentAndPower, percent: nil, temperature: nil, power: nil, isDaemonActive: true)
        XCTAssertEqual(voPower, "B-Guard, Akkustand – %, Akku-Leistung – W. \(MenuBarDisplayFormatter.powerNotice).")
    }

    // MARK: - Inactive Daemon

    func testInactiveDaemon() {
        // percentAndTemperature inactive
        let textTemp = MenuBarDisplayFormatter.text(for: .percentAndTemperature, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: false)
        XCTAssertEqual(textTemp, "– % – °C")

        let tipTemp = MenuBarDisplayFormatter.tooltip(for: .percentAndTemperature, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: false)
        XCTAssertEqual(tipTemp, "B-Guard · Hintergrunddienst nicht aktiv")

        let voTemp = MenuBarDisplayFormatter.voiceOverText(for: .percentAndTemperature, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: false)
        XCTAssertEqual(voTemp, "B-Guard: Hintergrunddienst nicht aktiv")

        // percentAndPower inactive (powerNotice must stay explicit)
        let textPower = MenuBarDisplayFormatter.text(for: .percentAndPower, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: false)
        XCTAssertEqual(textPower, "– % – W")

        let tipPower = MenuBarDisplayFormatter.tooltip(for: .percentAndPower, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: false)
        XCTAssertEqual(tipPower, "B-Guard · Dienst nicht aktiv. \(MenuBarDisplayFormatter.powerNotice).")

        let voPower = MenuBarDisplayFormatter.voiceOverText(for: .percentAndPower, percent: 85, temperature: 32.4, power: -10.0, isDaemonActive: false)
        XCTAssertEqual(voPower, "B-Guard: Hintergrunddienst nicht aktiv. \(MenuBarDisplayFormatter.powerNotice).")
    }

    // MARK: - Existing Modes Unchanged

    func testExistingModesRemainUnchanged() {
        // iconOnly
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .iconOnly, percent: 85, temperature: 30.0, power: 10.0, isDaemonActive: true), "")
        XCTAssertEqual(MenuBarDisplayFormatter.tooltip(for: .iconOnly, percent: 85, temperature: 30.0, power: 10.0, isDaemonActive: true), "B-Guard · Akkustand: 85 %")
        XCTAssertEqual(MenuBarDisplayFormatter.voiceOverText(for: .iconOnly, percent: 85, temperature: 30.0, power: 10.0, isDaemonActive: true), "B-Guard, Akkustand 85 %")

        // percent
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .percent, percent: 85, temperature: 30.0, power: 10.0, isDaemonActive: true), "85 %")
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .percent, percent: 85, temperature: 30.0, power: 10.0, isDaemonActive: false), "– %")

        // temperature
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .temperature, percent: 85, temperature: 31.2, power: 10.0, isDaemonActive: true), "31.2 °C")
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .temperature, percent: 85, temperature: 31.2, power: 10.0, isDaemonActive: false), "– °C")

        // power
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .power, percent: 85, temperature: 30.0, power: 12.3, isDaemonActive: true), "+12.3 W")
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .power, percent: 85, temperature: 30.0, power: 12.3, isDaemonActive: false), "– W")
    }
}
