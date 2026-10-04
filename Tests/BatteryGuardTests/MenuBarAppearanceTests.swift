import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

@Suite("MenuBarAppearanceTests")
struct MenuBarAppearanceTests {

    @Test("MenuBarIconStyle Fälle, Rohwerte und Titel")
    func testMenuBarIconStyleCasesAndTitles() {
        let allCases = MenuBarIconStyle.allCases
        #expect(allCases.count == 3)
        #expect(allCases == [.ring, .battery, .shield])

        #expect(MenuBarIconStyle.ring.rawValue == "ring")
        #expect(MenuBarIconStyle.battery.rawValue == "battery")
        #expect(MenuBarIconStyle.shield.rawValue == "shield")

        #expect(MenuBarIconStyle.appStorageKey == "bg.menuBarIconStyle")
        #expect(MenuBarIconStyle.defaultStyle == .ring)

        #expect(MenuBarIconStyle.ring.title == "Ladering")
        #expect(MenuBarIconStyle.battery.title == "Batterie")
        #expect(MenuBarIconStyle.shield.title == "Schild")
    }

    @Test("Akku-Symbol Clamp und SF-Symbol-Auswahl")
    func testBatterySymbolClampingAndNames() {
        #expect(MenuBarAppearance.clampPercent(-20) == 0)
        #expect(MenuBarAppearance.clampPercent(0) == 0)
        #expect(MenuBarAppearance.clampPercent(50) == 50)
        #expect(MenuBarAppearance.clampPercent(100) == 100)
        #expect(MenuBarAppearance.clampPercent(140) == 100)

        #expect(MenuBarAppearance.batterySymbolName(for: -5) == "battery.0percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 0) == "battery.0percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 12) == "battery.0percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 13) == "battery.25percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 37) == "battery.25percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 38) == "battery.50percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 62) == "battery.50percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 63) == "battery.75percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 87) == "battery.75percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 88) == "battery.100percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 100) == "battery.100percent")
        #expect(MenuBarAppearance.batterySymbolName(for: 120) == "battery.100percent")
    }

    @Test("Sichtbare Warnung bei fehlendem Hintergrunddienst")
    func testWarningWhenDaemonInactive() {
        var baseStatus = BGStatus()
        baseStatus.percent = 70
        baseStatus.pluggedIn = true
        let status = baseStatus

        let ringDesc = MenuBarAppearance.symbolDescriptor(style: .ring, status: status, isDaemonActive: false)
        #expect(ringDesc.isWarning == true)
        #expect(ringDesc.overlaySystemName == "exclamationmark")

        let batteryDesc = MenuBarAppearance.symbolDescriptor(style: .battery, status: status, isDaemonActive: false)
        #expect(batteryDesc.isWarning == true)
        #expect(batteryDesc.overlaySystemName == "exclamationmark")
        #expect(batteryDesc.baseSystemName == "battery.75percent")

        let shieldDesc = MenuBarAppearance.symbolDescriptor(style: .shield, status: status, isDaemonActive: false)
        #expect(shieldDesc.isWarning == true)
        #expect(shieldDesc.overlaySystemName == "exclamationmark")
    }

    @Test("Laden, Halten und Akkubetrieb für alle Symbolstile")
    func testChargingHoldingAndBatteryOperation() {
        // 1. Ladevorgang (pluggedIn = true, state != .holding)
        var chargingStatus = BGStatus()
        chargingStatus.percent = 80
        chargingStatus.pluggedIn = true
        chargingStatus.state = .charging
        chargingStatus.isChargingHardware = true
        let charging = chargingStatus

        let ringCharging = MenuBarAppearance.symbolDescriptor(style: .ring, status: charging, isDaemonActive: true)
        #expect(ringCharging.isWarning == false)
        #expect(ringCharging.overlaySystemName == "bolt.fill")

        let batteryCharging = MenuBarAppearance.symbolDescriptor(style: .battery, status: charging, isDaemonActive: true)
        #expect(batteryCharging.isWarning == false)
        #expect(batteryCharging.overlaySystemName == "bolt.fill")
        #expect(batteryCharging.baseSystemName == "battery.75percent")

        let shieldCharging = MenuBarAppearance.symbolDescriptor(style: .shield, status: charging, isDaemonActive: true)
        #expect(shieldCharging.isWarning == false)
        #expect(shieldCharging.overlaySystemName == "bolt.fill")

        // 2. Halten (state == .holding)
        var holdingStatus = BGStatus()
        holdingStatus.percent = 80
        holdingStatus.pluggedIn = true
        holdingStatus.state = .holding
        let holding = holdingStatus

        let ringHolding = MenuBarAppearance.symbolDescriptor(style: .ring, status: holding, isDaemonActive: true)
        #expect(ringHolding.isWarning == false)
        #expect(ringHolding.overlaySystemName == "pause.fill")

        let batteryHolding = MenuBarAppearance.symbolDescriptor(style: .battery, status: holding, isDaemonActive: true)
        #expect(batteryHolding.isWarning == false)
        #expect(batteryHolding.overlaySystemName == "pause.fill")

        let shieldHolding = MenuBarAppearance.symbolDescriptor(style: .shield, status: holding, isDaemonActive: true)
        #expect(shieldHolding.isWarning == false)
        #expect(shieldHolding.overlaySystemName == "pause.fill")

        // 3. Akkubetrieb (pluggedIn = false)
        var unpluggedStatus = BGStatus()
        unpluggedStatus.percent = 50
        unpluggedStatus.pluggedIn = false
        unpluggedStatus.state = .onBattery
        let unplugged = unpluggedStatus

        let ringUnplugged = MenuBarAppearance.symbolDescriptor(style: .ring, status: unplugged, isDaemonActive: true)
        #expect(ringUnplugged.isWarning == false)
        #expect(ringUnplugged.overlaySystemName == "arrow.down")

        let batteryUnplugged = MenuBarAppearance.symbolDescriptor(style: .battery, status: unplugged, isDaemonActive: true)
        #expect(batteryUnplugged.isWarning == false)
        #expect(batteryUnplugged.overlaySystemName == "arrow.down")
        #expect(batteryUnplugged.baseSystemName == "battery.50percent")

        let shieldUnplugged = MenuBarAppearance.symbolDescriptor(style: .shield, status: unplugged, isDaemonActive: true)
        #expect(shieldUnplugged.isWarning == false)
        #expect(shieldUnplugged.baseSystemName == "shield")
        #expect(shieldUnplugged.overlaySystemName == "arrow.down")
    }

    @Test func connectedAdapterDoesNotClaimChargingAndDischargeHasDirection() {
        var status = BGStatus()
        status.percent = 100
        status.pluggedIn = true
        status.state = .disabled
        for style in MenuBarIconStyle.allCases {
            let idle = MenuBarAppearance.symbolDescriptor(style: style, status: status, isDaemonActive: true)
            #expect(idle.overlaySystemName == nil)
            #expect(idle.accessibilityDescription.contains("lädt nicht"))
            status.state = .discharging
            let discharge = MenuBarAppearance.symbolDescriptor(style: style, status: status, isDaemonActive: true)
            #expect(discharge.overlaySystemName == "arrow.down")
            status.state = .unsupported
            let unsupported = MenuBarAppearance.symbolDescriptor(style: style, status: status, isDaemonActive: true)
            #expect(unsupported.isWarning)
            status.state = .disabled
        }
    }

    @Test("Reset-Helper setzt nur Menüleisten-Defaults zurück und erhält fremde Werte")
    func testResetDisplayPreferencesPreservesForeignKeys() {
        let suiteName = "BGuardTestUserDefaults.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults-Suite konnte nicht erstellt werden")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        // Fremde Einstellungen setzen (Ladeprofil, Mitteilungen, Autostart, API)
        defaults.set(true, forKey: "bg.notifyLow")
        defaults.set(15, forKey: "bg.lowBatteryThreshold")
        defaults.set("auto", forKey: "bg.chargeMode")
        defaults.set(80, forKey: "bg.chargeUpperLimit")
        defaults.set(true, forKey: "bg.launchAtLogin")
        defaults.set("secureLocalToken", forKey: "bg.localApiKey")

        // Benutzerdefinierte Menüleisten-Einstellungen setzen
        defaults.set("battery", forKey: "bg.menuBarIconStyle")
        defaults.set("watt", forKey: "bg.menuBarDisplay")
        defaults.set(true, forKey: "bg.menuShowTemperature")
        defaults.set(true, forKey: "bg.menuShowPower")
        defaults.set(true, forKey: "bg.menuShowHealth")

        // Mutierende Methode explizit außerhalb von #expect aufrufen
        MenuBarAppearance.resetDisplayPreferences(userDefaults: defaults)

        // 1. Zurückgesetzte Menüleisten-Defaults verifizieren
        let iconStyle = defaults.string(forKey: "bg.menuBarIconStyle")
        #expect(iconStyle == "ring")

        let displayMode = defaults.string(forKey: "bg.menuBarDisplay")
        #expect(displayMode == "percent")

        let showTemperature = defaults.bool(forKey: "bg.menuShowTemperature")
        #expect(showTemperature == false)

        let showPower = defaults.bool(forKey: "bg.menuShowPower")
        #expect(showPower == false)

        let showHealth = defaults.bool(forKey: "bg.menuShowHealth")
        #expect(showHealth == false)

        // 2. Erhalt aller fremden Werte verifizieren (niemals angetastet)
        let notifyLow = defaults.bool(forKey: "bg.notifyLow")
        #expect(notifyLow == true)

        let lowThreshold = defaults.integer(forKey: "bg.lowBatteryThreshold")
        #expect(lowThreshold == 15)

        let chargeMode = defaults.string(forKey: "bg.chargeMode")
        #expect(chargeMode == "auto")

        let chargeUpperLimit = defaults.integer(forKey: "bg.chargeUpperLimit")
        #expect(chargeUpperLimit == 80)

        let launchAtLogin = defaults.bool(forKey: "bg.launchAtLogin")
        #expect(launchAtLogin == true)

        let localApiKey = defaults.string(forKey: "bg.localApiKey")
        #expect(localApiKey == "secureLocalToken")
    }
}
