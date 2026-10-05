import Foundation
import BatteryGuardShared

public struct ControllerDecision: Sendable, Equatable {
    public var state: BGChargeState
    public var chargingEnabled: Bool
    public var adapterConnected: Bool
    public var resetChargeToFullOnce: Bool
    public var message: String?
    public var completedCalibrationRequestID: UUID? = nil
    public var updatedCalibrationPlan: BGCalibrationPlan? = nil
    public var completedSpecialRequestID: UUID? = nil
    public var updatedSpecialPlan: BGSpecialChargePlan? = nil
    public var heatProtectionThresholdCelsius: Int?
    public var heatProtectionActive: Bool

    public init(
        state: BGChargeState,
        chargingEnabled: Bool,
        adapterConnected: Bool,
        resetChargeToFullOnce: Bool = false,
        message: String? = nil,
        heatProtectionActive: Bool = false,
        heatProtectionThresholdCelsius: Int? = nil
    ) {
        self.state = state
        self.chargingEnabled = chargingEnabled
        self.adapterConnected = adapterConnected
        self.resetChargeToFullOnce = resetChargeToFullOnce
        self.message = message
        self.heatProtectionActive = heatProtectionActive
        self.heatProtectionThresholdCelsius = heatProtectionThresholdCelsius
    }
}

public enum ControllerLogic {
    public static let heatRecoveryMarginCelsius = 2.0

    private static func needsHeatProtection(config: BGConfig, battery: BatteryInfo,
                                            previousDecision: ControllerDecision?) -> Bool {
        let wasActive = previousDecision?.heatProtectionActive == true
        let configuredThreshold = config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius
            : (wasActive ? previousDecision?.heatProtectionThresholdCelsius ?? 0 : 0)
        guard configuredThreshold > 0 else { return false }
        guard let temperature = battery.temperatureCelsius, temperature.isFinite else {
            // A temporarily missing sensor reading is not evidence of cooling.
            return wasActive
        }
        let threshold = Double(configuredThreshold)
        return wasActive ? temperature > threshold - heatRecoveryMarginCelsius : temperature > threshold
    }

    private static func heatMessage(battery: BatteryInfo) -> String {
        guard let temperature = battery.temperatureCelsius, temperature.isFinite else {
            return "Hitzeschutz bleibt aktiv – Temperatur momentan nicht verfügbar"
        }
        return "Hitzeschutz aktiv: \(String(format: "%.1f", temperature))°C – Freigabe nach Abkühlung"
    }

    private static func preservingHeat(_ decision: ControllerDecision, config: BGConfig,
                                       battery: BatteryInfo, previousDecision: ControllerDecision?,
                                       hasChargeControl: Bool, now: Date) -> ControllerDecision {
        guard config.enabled, !config.isPaused(at: now), config.mode != .native, config.mode != .direct,
              (needsHeatProtection(config: config, battery: battery, previousDecision: previousDecision)
                || (config.heatProtectionCelsius > 0 && (battery.temperatureCelsius.map { $0.isFinite && $0 >= Double(config.heatProtectionCelsius) } ?? false))) else { return decision }
        var protected = decision
        protected.heatProtectionActive = true
        protected.heatProtectionThresholdCelsius = config.heatProtectionCelsius > 0
            ? config.heatProtectionCelsius : previousDecision?.heatProtectionThresholdCelsius
        protected.adapterConnected = true
        if hasChargeControl {
            protected.chargingEnabled = false
            protected.state = .holding
            protected.message = heatMessage(battery: battery)
        } else {
            protected.message = "Hitzeschutz erforderlich – ohne separate Ladesteuerung kann Laden nicht gesperrt werden"
        }
        return protected
    }

    /// Reine, testbare Regellogik-Funktion ohne Seiteneffekte
    public static func evaluate(
        config: BGConfig,
        battery: BatteryInfo,
        previousDecision: ControllerDecision?,
        hasChargeControl: Bool,
        hasDischargeControl: Bool,
        allowsAdapterDisconnect: Bool = true,
        specialHardwareVerified: Bool = false,
        now: Date = Date()
    ) -> ControllerDecision {
        if let plan = config.calibrationPlan {
            let adapterDisabled = previousDecision?.adapterConnected == false
            let power: BGExternalPowerState = !battery.externalPowerAvailable || adapterDisabled
                ? .unknown : (battery.pluggedIn ? .connected : .disconnected)
            var heatConfig = config
            heatConfig.heatProtectionCelsius = config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : 40
            let heatActive = needsHeatProtection(config: heatConfig, battery: battery, previousDecision: previousDecision)
                || (battery.temperatureCelsius.map { $0.isFinite && $0 >= Double(heatConfig.heatProtectionCelsius) } ?? false)
            let verified = specialHardwareVerified && hasChargeControl && hasDischargeControl
                && allowsAdapterDisconnect && config.enabled && !config.isPaused(at: now)
                && config.mode != .native && config.mode != .direct
            let context = BGCalibrationContext(
                percent: battery.percentAvailable && (0...100).contains(battery.percent) ? battery.percent : nil,
                externalPower: power,
                temperatureCelsius: battery.temperatureCelsius.flatMap { $0.isFinite ? $0 : nil },
                heatThreshold: heatConfig.heatProtectionCelsius, heatActive: heatActive,
                hardwareVerified: verified, adapterDisabledByUs: adapterDisabled)
            var decision: ControllerDecision
            switch plan.evaluate(context: context, at: now) {
            case .unavailable(let reason):
                decision = ControllerDecision(state: .unsupported, chargingEnabled: true, adapterConnected: true,
                    message: "Kalibrierung nicht verfügbar: " + reason)
                decision.completedCalibrationRequestID = plan.requestID
            case .complete(let reason):
                decision = ControllerDecision(state: .disabled, chargingEnabled: true, adapterConnected: true,
                    message: "Kalibrierung beendet: " + reason)
                decision.completedCalibrationRequestID = plan.requestID
            case .paused(let updated, let reason):
                decision = ControllerDecision(state: heatActive ? .holding : .disabled,
                    chargingEnabled: !heatActive, adapterConnected: true,
                    message: heatActive ? heatMessage(battery: battery) : "Kalibrierung pausiert: " + reason,
                    heatProtectionActive: heatActive)
                decision.updatedCalibrationPlan = updated
            case .active(let updated, let command):
                switch command {
                case .charge:
                    decision = ControllerDecision(state: .charging, chargingEnabled: true, adapterConnected: true,
                        message: "Kalibrierung: " + updated.phase.rawValue)
                case .hold:
                    decision = ControllerDecision(state: .holding, chargingEnabled: false, adapterConnected: true,
                        message: "Kalibrierung: 100 % eine Stunde halten")
                case .discharge:
                    decision = ControllerDecision(state: .discharging, chargingEnabled: false, adapterConnected: false,
                        message: "Kalibrierung: auf 10 % entladen")
                }
                decision.updatedCalibrationPlan = updated
            }
            return preservingHeat(decision, config: heatConfig, battery: battery,
                previousDecision: previousDecision, hasChargeControl: hasChargeControl, now: now)
        }
        if let plan = config.specialChargePlan {
            var decision: ControllerDecision
            let adapterDisabled = previousDecision?.adapterConnected == false
            let power: BGExternalPowerSource = !battery.externalPowerAvailable || adapterDisabled
                ? .unknown : (battery.pluggedIn ? .connected : .disconnected)
            let context = BGSpecialPlanEvaluationContext(
                percent: battery.percentAvailable ? battery.percent : nil,
                externalPower: power, canBlockCharging: hasChargeControl && specialHardwareVerified,
                canDisconnectAdapter: hasDischargeControl && specialHardwareVerified,
                allowsAdapterDisconnect: allowsAdapterDisconnect)
            let outcome = plan.evaluate(context: context, at: now)
            let supported = config.enabled && !config.isPaused(at: now) && config.mode != .native && config.mode != .direct
                && hasChargeControl && (plan.kind != .discharge || (specialHardwareVerified && hasDischargeControl && allowsAdapterDisconnect))
                && (plan.kind != .hold || specialHardwareVerified)
            guard supported && outcome.isActive else {
                decision = ControllerDecision(state: outcome.isComplete ? .disabled : .unsupported,
                    chargingEnabled: true, adapterConnected: true,
                    message: supported ? outcome.reason : "Sonderaktion auf dieser Hardware nicht bestätigt – Normalbetrieb wiederhergestellt")
                decision.completedSpecialRequestID = plan.requestID
                return preservingHeat(decision, config: config, battery: battery,
                    previousDecision: previousDecision, hasChargeControl: hasChargeControl, now: now)
            }
            if needsHeatProtection(config: config, battery: battery, previousDecision: previousDecision) {
                decision = ControllerDecision(state: .holding, chargingEnabled: false, adapterConnected: true,
                    message: heatMessage(battery: battery), heatProtectionActive: true, heatProtectionThresholdCelsius: config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : previousDecision?.heatProtectionThresholdCelsius)
            } else if power == .disconnected {
                decision = ControllerDecision(state: .onBattery, chargingEnabled: true, adapterConnected: true, message: outcome.reason)
            } else {
                switch plan.kind {
                case .topUp:
                    let charging = battery.percent < 100
                    decision = ControllerDecision(state: charging ? .charging : .holding,
                        chargingEnabled: charging, adapterConnected: true, message: outcome.reason)
                case .hold:
                    let charging = battery.percent >= plan.targetPercent ? false
                        : battery.percent < max(5, plan.targetPercent - 2) ? true
                        : (previousDecision?.heatProtectionActive == true ? true : previousDecision?.chargingEnabled ?? battery.isCharging)
                    decision = ControllerDecision(state: charging ? .charging : .holding,
                        chargingEnabled: charging, adapterConnected: true, message: outcome.reason)
                case .discharge:
                    decision = ControllerDecision(state: .discharging, chargingEnabled: false,
                        adapterConnected: false, message: outcome.reason)
                }
            }
            decision.updatedSpecialPlan = outcome.updatedPlan
            return decision
        }
        guard battery.percentAvailable else {
            return preservingHeat(ControllerDecision(state: .unsupported, chargingEnabled: true, adapterConnected: true,
                message: "Ladestand nicht verfügbar – Normalbetrieb wiederhergestellt"), config: config,
                battery: battery, previousDecision: previousDecision, hasChargeControl: hasChargeControl, now: now)
        }
        let config = config.effective(at: now)
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
                heatProtectionActive: true,
                    heatProtectionThresholdCelsius: config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : previousDecision?.heatProtectionThresholdCelsius
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
                    heatProtectionActive: true,
                    heatProtectionThresholdCelsius: config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : previousDecision?.heatProtectionThresholdCelsius
                )
            }
            return ControllerDecision(
                state: .discharging, chargingEnabled: false, adapterConnected: false,
                message: heatMessage(battery: battery),
                heatProtectionActive: true,
                    heatProtectionThresholdCelsius: config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : previousDecision?.heatProtectionThresholdCelsius
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

/// Apply tick results only to the exact request read by that tick.
public enum SpecialControllerPersistence {
    public static func apply(snapshot: BGSpecialChargePlan, decision: ControllerDecision, to latest: inout BGConfig) {
        guard latest.specialChargePlan?.requestID == snapshot.requestID else { return }
        if decision.completedSpecialRequestID == snapshot.requestID {
            latest.specialChargePlan = nil
        } else if let updated = decision.updatedSpecialPlan, updated.requestID == snapshot.requestID {
            latest.specialChargePlan = updated
        }
    }
}

public enum CalibrationControllerPersistence {
    public static func apply(snapshot: BGCalibrationPlan, decision: ControllerDecision, to latest: inout BGConfig) {
        guard latest.calibrationPlan?.requestID == snapshot.requestID else { return }
        if decision.completedCalibrationRequestID == snapshot.requestID {
            latest.calibrationPlan = nil
        } else if let updated = decision.updatedCalibrationPlan, updated.requestID == snapshot.requestID {
            latest.calibrationPlan = updated
        }
    }
}
