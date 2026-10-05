import XCTest
@testable import BatteryGuard
import BatteryGuardShared

final class MenuBarDisplayTests: XCTestCase {

    func testEnumCasesAndRawValues() {
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 6)
        XCTAssertEqual(MenuBarDisplayMode.iconOnly.rawValue, "iconOnly")
        XCTAssertEqual(MenuBarDisplayMode.percent.rawValue, "percent")
        XCTAssertEqual(MenuBarDisplayMode.temperature.rawValue, "temperature")
        XCTAssertEqual(MenuBarDisplayMode.power.rawValue, "power")

        XCTAssertEqual(MenuBarDisplayMode.iconOnly.title, "Symbol allein")
        XCTAssertEqual(MenuBarDisplayMode.percent.title, "Prozent")
        XCTAssertEqual(MenuBarDisplayMode.temperature.title, "Akkutemperatur")
        XCTAssertEqual(MenuBarDisplayMode.power.title, "Akku-Leistung")

        XCTAssertEqual(MenuBarDisplayMode.appStorageKey, "bg.menuBarDisplay")
        XCTAssertEqual(MenuBarDisplayMode.defaultMode, .percent)
    }

    func testEnumFromRawString() {
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "percent"), .percent)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "prozent"), .percent)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "iconOnly"), .iconOnly)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "symbol"), .iconOnly)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "temperature"), .temperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "akkutemperatur"), .temperature)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "power"), .power)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "akku-leistung"), .power)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: "unknown"), .percent)
        XCTAssertEqual(MenuBarDisplayMode(fromRawString: nil), .percent)
    }

    func testPercentClamping() {
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(-20), 0)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(0), 0)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(50), 50)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(100), 100)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(120), 100)

        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(-5.5 as Double), 0)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(85.4 as Double), 85)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(105.2 as Double), 100)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(Double.nan), 0)
    }

    func testPercentFormatting() {
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(80, isDaemonActive: true), "80 %")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(-10, isDaemonActive: true), "0 %")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(125, isDaemonActive: true), "100 %")

        // Inaktiver Dienst oder fehlende / nichtfinite Werte als Gedankenstrich
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(80, isDaemonActive: false), "– %")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(nil as Int?, isDaemonActive: true), "– %")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(Double.nan, isDaemonActive: true), "– %")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPercent(Double.infinity, isDaemonActive: true), "– %")
    }

    func testTemperatureFormatting() {
        // Ein Nachkomma mit °C
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(28.5, isDaemonActive: true), "28.5 °C")
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(32.0, isDaemonActive: true), "32.0 °C")
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(35.49, isDaemonActive: true), "35.5 °C")

        // Inaktiver Dienst oder fehlende / nichtfinite Werte als Gedankenstrich
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(28.5, isDaemonActive: false), "– °C")
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(nil, isDaemonActive: true), "– °C")
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(Double.nan, isDaemonActive: true), "– °C")
        XCTAssertEqual(MenuBarDisplayFormatter.formatTemperature(Double.infinity, isDaemonActive: true), "– °C")
    }

    func testPowerFormattingSigned() {
        // Ein Nachkomma mit W signed (+/-)
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(14.2, isDaemonActive: true), "+14.2 W")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(-6.8, isDaemonActive: true), "-6.8 W")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(0.0, isDaemonActive: true), "+0.0 W")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(24.55, isDaemonActive: true), "+24.6 W")

        // Inaktiver Dienst oder fehlende / nichtfinite Werte als Gedankenstrich
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(14.2, isDaemonActive: false), "– W")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(nil, isDaemonActive: true), "– W")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(Double.nan, isDaemonActive: true), "– W")
        XCTAssertEqual(MenuBarDisplayFormatter.formatPower(Double.infinity, isDaemonActive: true), "– W")
    }

    func testDisplayTextForModes() {
        // Symbol allein
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .iconOnly, percent: 75, temperature: 30.0, power: 10.0, isDaemonActive: true),
            ""
        )

        // Prozent
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .percent, percent: 75, temperature: 30.0, power: 10.0, isDaemonActive: true),
            "75 %"
        )
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .percent, percent: 75, temperature: 30.0, power: 10.0, isDaemonActive: false),
            "– %"
        )

        // Temperatur
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .temperature, percent: 75, temperature: 31.2, power: 10.0, isDaemonActive: true),
            "31.2 °C"
        )
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .temperature, percent: 75, temperature: nil, power: 10.0, isDaemonActive: true),
            "– °C"
        )

        // Leistung
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .power, percent: 75, temperature: 31.2, power: 15.4, isDaemonActive: true),
            "+15.4 W"
        )
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .power, percent: 75, temperature: 31.2, power: -8.1, isDaemonActive: true),
            "-8.1 W"
        )
        XCTAssertEqual(
            MenuBarDisplayFormatter.text(for: .power, percent: 75, temperature: 31.2, power: nil, isDaemonActive: true),
            "– W"
        )
    }

    func testTypedSensorValuesKeepTheirDeclaredUnits() {
        var status = BGStatus()
        status.temperatureCelsius = 250
        status.watts = -250
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .temperature, status: status, isDaemonActive: true), "250.0 °C")
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .power, status: status, isDaemonActive: true), "-250.0 W")
        status.temperatureCelsius = nil
        status.watts = nil
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .temperature, status: status, isDaemonActive: true), "– °C")
        XCTAssertEqual(MenuBarDisplayFormatter.text(for: .power, status: status, isDaemonActive: true), "– W")
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(Double.greatestFiniteMagnitude), 100)
        XCTAssertEqual(MenuBarDisplayFormatter.clampPercent(-Double.greatestFiniteMagnitude), 0)
    }

    func testVoiceOverAndTooltipContainPowerExplanation() {
        let tooltip = MenuBarDisplayFormatter.tooltip(for: .power, percent: 80, temperature: 29.0, power: 12.0, isDaemonActive: true)
        XCTAssertTrue(
            tooltip.contains("Akku-Leistung ist Lade-/Entladefluss, nicht gesamte Mac-Leistung"),
            "Tooltip muss den geforderten Erklärungstext für Akku-Leistung enthalten"
        )

        let voiceOver = MenuBarDisplayFormatter.voiceOverText(for: .power, percent: 80, temperature: 29.0, power: -7.5, isDaemonActive: true)
        XCTAssertTrue(
            voiceOver.contains("Akku-Leistung ist Lade-/Entladefluss, nicht gesamte Mac-Leistung"),
            "VoiceOver-Text muss den geforderten Erklärungstext für Akku-Leistung enthalten"
        )
    }
}
