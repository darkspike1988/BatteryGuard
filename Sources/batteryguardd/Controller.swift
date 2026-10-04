import Foundation
import BatteryGuardShared

public struct ControllerDecision: Sendable, Equatable {
    public var state: BGChargeState
    public var chargingEnabled: Bool
    public var adapterConnected: Bool
    public var resetChargeToFullOnce: Bool
    public var message: String?
    public var heatProtectionActive: Bool

    public init(
        state: BGChargeState,
        chargingEnabled: Bool,
        adapterConnected: Bool,
        resetChargeToFullOnce: Bool = false,
        message: String? = nil,
        heatProtectionActive: Bool = false
    ) {
        self.state = state
        self.chargingEnabled = chargingEnabled
        self.adapterConnected = adapterConnected
        self.resetChargeToFullOnce = resetChargeToFullOnce
        self.message = message
        self.heatProtectionActive = heatProtectionActive
    }
}

public enum ControllerLogic {
    public static let heatRecoveryMarginCelsius = 2.0

    private static func needsHeatProtection(config: BGConfig, battery: BatteryInfo,
                                            previousDecision: ControllerDecision?) -> Bool {
        guard config.heatProtectionCelsius > 0 else { return false }
        let wasActive = previousDecision?.heatProtectionActive == true
        guard let temperature = battery.temperatureCelsius, temperature.isFinite else {
            // A temporarily missing sensor reading is not evidence of cooling.
            return wasActive
        }
        let threshold = Double(config.heatProtectionCelsius)
        return wasActive ? temperature > threshold - heatRecoveryMarginCelsius : temperature > threshold
    }

    private static func heatMessage(battery: BatteryInfo) -> String {
        guard let temperature = battery.temperatureCelsius, temperature.isFinite else {
            return "Hitzeschutz bleibt aktiv – Temperatur momentan nicht verfügbar"
        }
        return "Hitzeschutz aktiv: \(String(format: "%.1f", temperature))°C – Freigabe nach Abkühlung"
    }

    /// Reine, testbare Regellogik-Funktion ohne Seiteneffekte
    public static func evaluate(
        config: BGConfig,
        battery: BatteryInfo,
        previousDecision: ControllerDecision?,
        hasChargeControl: Bool,
        hasDischargeControl: Bool,
        allowsAdapterDisconnect: Bool = true
    ) -> ControllerDecision {
        // Das von uns selbst deaktivierte Netzteil meldet sich evtl. als "nicht angesteckt".
        // Dann gilt es weiterhin als angesteckt, sonst würden wir zwischen den Zuständen flattern.
        let adapterDisabledByUs = previousDecision?.adapterConnected == false
        let effectivelyPlugged = battery.pluggedIn || adapterDisabledByUs
        
        // 0. Modus-Prüfung
        if config.mode == .native {
            return ControllerDecision(
                state: .disabled,
                chargingEnabled: true,
                adapterConnected: true,
                resetChargeToFullOnce: false,
                message: "Natives macOS-Limit aktiv (App greift nicht ein)"
            )
        }

        // Der experimentelle Direktmodus ist nicht implementiert. Niemals still auf
        // aktive Entladung umschalten, wenn dieser Modus ausgewählt wurde.
        if config.mode == .direct {
            return ControllerDecision(state: .unsupported, chargingEnabled: true,
                                      adapterConnected: true,
                                      message: "Direktmodus nicht implementiert – bitte Auto, Nativ oder Pendel wählen")
        }

        // 1. Hardware/SMC-Unterstützung prüfen
        guard hasChargeControl && config.mode != .pendulum else {
            // macOS 26.4+/27: CHTE/CH0B (Ladesperre) existieren nicht mehr.
            // Fallback "Pendel-Modus": nur über den Netzteil-Schalter (CHIE/CH0J/CH0I) arbeiten.
            guard hasDischargeControl else {
                return ControllerDecision(
                    state: .unsupported,
                    chargingEnabled: true,
                    adapterConnected: true,
                    resetChargeToFullOnce: false,
                    message: "Keine unterstützten SMC-Schlüssel für Ladesteuerung gefunden (weder CHTE/CH0B noch CHIE/CH0J/CH0I)."
                )
            }
            if config.enabled && effectivelyPlugged && !allowsAdapterDisconnect {
                return ControllerDecision(state: .disabled, chargingEnabled: true, adapterConnected: true,
                    message: "Monitor-/Deckelschutz: Netzteil bleibt verbunden. Ohne separate Ladesperre übernimmt macOS das Ladelimit.")
            }
            return evaluatePendulum(
                config: config,
                battery: battery,
                previousDecision: previousDecision,
                effectivelyPlugged: effectivelyPlugged
            )
        }

        // 2. Ohne Netzteil: alle SMC-Schalter auf normal, state = .onBattery
        guard effectivelyPlugged else {
            return ControllerDecision(
                state: .onBattery,
                chargingEnabled: true,
                adapterConnected: true,
                resetChargeToFullOnce: config.chargeToFullOnce && battery.percent >= 100,
                message: nil
            )
        }


        // 3. Schutz deaktiviert (enabled = false): Laden an + Adapter an, state = .disabled
        guard config.enabled else {
            return ControllerDecision(
                state: .disabled,
                chargingEnabled: true,
                adapterConnected: true,
                resetChargeToFullOnce: config.chargeToFullOnce && battery.percent >= 100,
                message: "Batterieschutz deaktiviert"
            )
        }

        // 5. Hitzeschutz: temperatur > heatProtectionCelsius → Laden aus
        if needsHeatProtection(config: config, battery: battery, previousDecision: previousDecision) {
            return ControllerDecision(
                state: .holding,
                chargingEnabled: false,
                adapterConnected: true,
                resetChargeToFullOnce: false,
                message: heatMessage(battery: battery),
                heatProtectionActive: true
            )
        }

        // 4. Einmalig voll laden (chargeToFullOnce): bis 100% laden
        if config.chargeToFullOnce {
            if battery.percent >= 100 {
                return ControllerDecision(
                    state: .holding,
                    chargingEnabled: false,
                    adapterConnected: true,
                    resetChargeToFullOnce: true,
                    message: "Einmaliges Vollladen abgeschlossen (100 %)"
                )
            } else {
                return ControllerDecision(
                    state: .charging,
                    chargingEnabled: true,
                    adapterConnected: true,
                    resetChargeToFullOnce: false,
                    message: "Einmaliges Vollladen aktiv (\(battery.percent) %)"
                )
            }
        }

        // 6. Aktives Entladen am Kabel: bei percent > upperLimit Adapter trennen
        //    bis percent <= upperLimit, dann Adapter wieder an und Laden aus.
        if config.activeDischargeAboveUpper && hasDischargeControl && allowsAdapterDisconnect {
            if battery.percent > config.upperLimit {
                return ControllerDecision(
                    state: .discharging,
                    chargingEnabled: false,
                    adapterConnected: false,
                    resetChargeToFullOnce: false,
                    message: "Aktives Entladen auf \(config.upperLimit) % (aktuell \(battery.percent) %)"
                )
            }
            // Wenn percent <= upperLimit erreicht wurde, fällt die Logik unten in die Hysterese
            // mit adapterConnected = true und chargingEnabled = false (.holding).
        }

        // 7. Hysterese für normales Laden am Netzteil:
        //    percent >= upperLimit → Laden aus (.holding)
        //    percent < lowerLimit → Laden an (.charging)
        //    dazwischen → bisherigen Ladezustand beibehalten
        if battery.percent >= config.upperLimit {
            return ControllerDecision(
                state: .holding,
                chargingEnabled: false,
                adapterConnected: true,
                resetChargeToFullOnce: false,
                message: "Ladelimit von \(config.upperLimit) % erreicht"
            )
        } else if battery.percent < config.lowerLimit {
            return ControllerDecision(
                state: .charging,
                chargingEnabled: true,
                adapterConnected: true,
                resetChargeToFullOnce: false,
                message: "Laden aktiv bis \(config.upperLimit) %"
            )
        } else {
            // Zwischen lowerLimit und upperLimit: Vorherigen Zustand beibehalten
            let isCharging: Bool
            if let prev = previousDecision {
                isCharging = prev.heatProtectionActive ? true : prev.chargingEnabled
            } else {
                isCharging = battery.isCharging
            }

            return ControllerDecision(
                state: isCharging ? .charging : .holding,
                chargingEnabled: isCharging,
                adapterConnected: true,
                resetChargeToFullOnce: false,
                message: isCharging ? "Laden aktiv bis \(config.upperLimit) %" : "Ladelimit von \(config.upperLimit) % gehalten"
            )
        }
    }

    /// Hysterese (in Prozentpunkten) des Pendel-Modus: Netzteil geht bei >= upperLimit aus
    /// und erst bei <= upperLimit - pendulumHysteresis wieder an.
    public static let pendulumHysteresis = 5

    /// Fallback ohne Ladesperre-Key: Das Limit wird nur über das Ein-/Ausschalten des Netzteils
    /// (CHIE/CH0J/CH0I) erzwungen. Der Akku pendelt dadurch zwischen (upper - 5) und upper.
    static func evaluatePendulum(
        config: BGConfig,
        battery: BatteryInfo,
        previousDecision: ControllerDecision?,
        effectivelyPlugged: Bool
    ) -> ControllerDecision {
        let normal = { (state: BGChargeState, msg: String?, reset: Bool) in
            ControllerDecision(state: state, chargingEnabled: true, adapterConnected: true,
                               resetChargeToFullOnce: reset, message: msg)
        }

        guard effectivelyPlugged else {
            return normal(.onBattery, nil, config.chargeToFullOnce && battery.percent >= 100)
        }
        guard config.enabled else {
            return normal(.disabled, "Batterieschutz deaktiviert", config.chargeToFullOnce && battery.percent >= 100)
        }
        // Hitzeschutz: lieber vom Akku laufen als heiß weiter laden
        if needsHeatProtection(config: config, battery: battery, previousDecision: previousDecision) {
            // Once the reserve is reached, keep AC connected until cooling. Otherwise
            // charging one percent would immediately disconnect it again while still hot.
            let reserveReached = battery.percent <= config.lowerLimit
                || (previousDecision?.heatProtectionActive == true && previousDecision?.adapterConnected == true)
            if reserveReached {
                return ControllerDecision(
                    state: .charging, chargingEnabled: true, adapterConnected: true,
                    message: "Akkureserve erreicht: Netzteil bleibt bis zur Abkühlung verbunden. Ohne separate Ladesperre kann Hitzeschutz das Laden nicht stoppen.",
                    heatProtectionActive: true
                )
            }
            return ControllerDecision(
                state: .discharging, chargingEnabled: false, adapterConnected: false,
                message: heatMessage(battery: battery),
                heatProtectionActive: true
            )
        }

        if config.chargeToFullOnce {
            if battery.percent >= 100 {
                return normal(.holding, "Einmaliges Vollladen abgeschlossen (100 %)", true)
            }
            return normal(.charging, "Einmaliges Vollladen aktiv (\(battery.percent) %)", false)
        }

        let resumeLevel = max(config.upperLimit - pendulumHysteresis, config.lowerLimit)
        var adapterOff = previousDecision?.adapterConnected == false

        if battery.percent >= config.upperLimit {
            adapterOff = true
        } else if battery.percent <= resumeLevel {
            adapterOff = false
        }

        if adapterOff {
            return ControllerDecision(
                state: .discharging, chargingEnabled: false, adapterConnected: false,
                message: "Pendel-Modus: Akku läuft ab \(config.upperLimit) % bis \(resumeLevel) % vom Akku"
            )
        }
        return ControllerDecision(
            state: .charging, chargingEnabled: true, adapterConnected: true,
            message: "Pendel-Modus: lädt bis \(config.upperLimit) %"
        )
    }
}


public final class BatteryController: @unchecked Sendable {
    public let smc: SMCClient
    private var previousDecision: ControllerDecision?
    private var lastAppliedCharging: Bool?
    private var lastAppliedAdapter: Bool?
    private var lastAppliedMagSafeLED: SMCClient.MagSafeColor?
    private var lastHardwareCheckUptime: TimeInterval?
    private let lock = NSLock()

    public init(smc: SMCClient = .shared) {
        self.smc = smc
    }

    public func step(
        config: BGConfig,
        battery: BatteryInfo,
        dryRun: Bool,
        logger: ((String) -> Void)? = nil
    ) -> ControllerDecision {
        lock.lock()
        defer { lock.unlock() }

        let uptime = ProcessInfo.processInfo.systemUptime
        if !dryRun && (lastHardwareCheckUptime.map { uptime - $0 >= 60 } ?? true) {
            lastHardwareCheckUptime = uptime
            if smc.hasChargeControl, let expected = lastAppliedCharging {
                let result = smc.verifyChargingEnabled(expected)
                if result != .matches {
                    // Keep the logical decision: hardware drift must not reset hysteresis.
                    lastAppliedCharging = nil
                    logger?("SMC: Lade-Readback \(result == .drift ? "weicht ab" : "nicht verifizierbar") – Zielzustand wird erneut geprüft.")
                }
            }
            if smc.hasDischargeControl, let expected = lastAppliedAdapter {
                let result = smc.verifyAdapterConnected(expected)
                if result != .matches {
                    lastAppliedAdapter = nil
                    logger?("SMC: Netzteil-Readback \(result == .drift ? "weicht ab" : "nicht verifizierbar") – Zielzustand wird erneut geprüft.")
                }
            }
        }

        let decision = ControllerLogic.evaluate(
            config: config,
            battery: battery,
            previousDecision: previousDecision,
            hasChargeControl: smc.hasChargeControl,
            hasDischargeControl: smc.hasDischargeControl,
            allowsAdapterDisconnect: DesktopEnvironment.allowsAdapterDisconnect()
        )

        var controlFailed = false

        // MagSafe LED bestimmen
        let targetLED: SMCClient.MagSafeColor
        if !config.magsafeLed || !config.enabled {
            targetLED = .auto
        } else if decision.state == .holding {
            targetLED = .green
        } else if decision.state == .charging {
            targetLED = .orange
        } else {
            targetLED = .auto
        }

        // SMC nur anpassen, wenn nicht dry-run und sich der Zielzustand geändert hat (kein Write-Spam)
        if !dryRun && (smc.hasChargeControl || smc.hasDischargeControl || smc.keyExists("ACLC")) {
            if smc.hasChargeControl && decision.chargingEnabled != lastAppliedCharging {
                let success = smc.setChargingEnabled(decision.chargingEnabled)
                logger?("SMC: setChargingEnabled(\(decision.chargingEnabled)) => \(success ? "ok" : "failed")")
                if success {
                    lastAppliedCharging = decision.chargingEnabled
                } else {
                    controlFailed = true
                }
            }

            if smc.hasDischargeControl && decision.adapterConnected != lastAppliedAdapter {
                let success = smc.setAdapterConnected(decision.adapterConnected)
                logger?("SMC: setAdapterConnected(\(decision.adapterConnected)) => \(success ? "ok" : "failed")")
                if success {
                    lastAppliedAdapter = decision.adapterConnected

                } else {
                    controlFailed = true
                }
            }
            
            if smc.keyExists("ACLC") && targetLED != lastAppliedMagSafeLED {
                let success = smc.setMagSafeLED(targetLED)
                logger?("SMC: setMagSafeLED(\(targetLED)) => \(success ? "ok" : "failed")")
                if success {
                    lastAppliedMagSafeLED = targetLED
                }
            }
        } else if dryRun {
            if decision.chargingEnabled != lastAppliedCharging {
                logger?("[DRY-RUN] SMC: Würde setChargingEnabled(\(decision.chargingEnabled)) ausführen")
                lastAppliedCharging = decision.chargingEnabled
            }
            if decision.adapterConnected != lastAppliedAdapter {
                logger?("[DRY-RUN] SMC: Würde setAdapterConnected(\(decision.adapterConnected)) ausführen")
                lastAppliedAdapter = decision.adapterConnected
            }
            if targetLED != lastAppliedMagSafeLED {
                logger?("[DRY-RUN] SMC: Würde setMagSafeLED(\(targetLED)) ausführen")
                lastAppliedMagSafeLED = targetLED
            }
        }

        if controlFailed {
            // Nicht als erfolgreiches Halten/Entladen anzeigen, wenn SMC ablehnt.
            return ControllerDecision(state: .unsupported,
                chargingEnabled: lastAppliedCharging ?? true,
                adapterConnected: lastAppliedAdapter ?? true,
                message: "SMC-Steuerung fehlgeschlagen – Ladezustand konnte nicht angewendet werden")
        }
        previousDecision = decision
        return decision
    }

    public func invalidateHardwareCache() {
        lock.lock()
        defer { lock.unlock() }
        previousDecision = nil
        lastAppliedCharging = nil
        lastAppliedAdapter = nil
        lastAppliedMagSafeLED = nil
        lastHardwareCheckUptime = nil
    }

    public func restoreNormal(logger: ((String) -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if smc.hasChargeControl || smc.hasDischargeControl || smc.keyExists("ACLC") {
            let success = smc.restoreNormal()
            logger?(success ? "SMC: Alle unterstützten Schalter auf Normalbetrieb zurückgesetzt."
                            : "SMC: Wiederherstellung mindestens eines Schalters fehlgeschlagen.")
            if !success {
                previousDecision = nil
                lastAppliedCharging = nil
                lastAppliedAdapter = nil
                lastAppliedMagSafeLED = nil
                return
            }
        }
        previousDecision = nil
        lastAppliedCharging = true
        lastAppliedAdapter = true
        lastAppliedMagSafeLED = .auto
    }
}
