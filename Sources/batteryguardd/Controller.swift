import Foundation
import BatteryGuardShared

public struct ControllerDecision: Sendable, Equatable {
    public var state: BGChargeState
    public var chargingEnabled: Bool
    public var adapterConnected: Bool
    public var resetChargeToFullOnce: Bool
    public var message: String?
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

/// Setzt das macOS-Ladelimit über PowerUIAgent. Nur im Dienst, nur mit root.
public protocol NativeChargeLimitDriving: AnyObject, Sendable {
    var isSupported: Bool { get }
    /// Der Dienst hat das Limit übernommen und den vorherigen Wert gesichert.
    var hasTakenControl: Bool { get }
    /// Der Wert, den PowerUIAgent gerade anwendet.
    func currentLimit() -> Int?
    /// Schreibt das Limit und prüft, ob macOS es übernommen hat.
    func apply(_ percent: Int) -> Bool
    /// Stellt den vorherigen Wert wieder her (mindestens 80 %, damit er in den
    /// Systemeinstellungen sichtbar bleibt) und gibt die Kontrolle ab.
    @discardableResult func release() -> Bool
}

public enum ControllerLogic {
    public static let heatRecoveryMarginCelsius = 2.0
    /// macOS selbst bietet nur 80–100 % an.
    public static let nativeLimitSystemMinimum = 80
    /// Darunter lädt der Mac praktisch nicht mehr; Werte unter 80 % sind ohnehin experimentell.
    public static let nativeLimitAbsoluteMinimum = 20

    /// Leitet das macOS-Ladelimit aus derselben Entscheidung ab wie die SMC-Ladesperre.
    /// „Laden aus“ unterhalb des Ziels hält den aktuellen Stand, so bleiben Hysterese und
    /// Hitzeschutz erhalten. Liegt das Limit unter dem Ladestand, entlädt macOS am Netzteil
    /// bis dorthin; das geschieht nur mit aktivem Entladen über dem Limit.
    public static func nativeCeiling(decision: ControllerDecision, config: BGConfig, battery: BatteryInfo,
                                     allowBelow80: Bool, now: Date = Date()) -> Int {
        let effective = config.effective(at: now)
        let target: Int
        if let plan = effective.specialChargePlan, plan.kind == .hold {
            target = plan.targetPercent
        } else if effective.chargeToFullOnce {
            target = 100
        } else {
            target = effective.upperLimit
        }
        let ceiling: Int
        if decision.heatProtectionActive || (!decision.chargingEnabled && battery.percent < target) {
            ceiling = battery.percent
        } else if effective.activeDischargeAboveUpper {
            ceiling = target
        } else {
            ceiling = max(target, battery.percent)
        }
        let minimum = allowBelow80 ? nativeLimitAbsoluteMinimum : nativeLimitSystemMinimum
        return min(100, max(minimum, ceiling))
    }

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
                                      message: "Direktmodus nicht implementiert – bitte Auto oder Nativ wählen")
        }

        // 1. Ohne separate SMC-Ladesperre setzt macOS das Limit durch (Systemeinstellungen →
        //    Batterie → Ladelimit, ab macOS 26.4). B-Guard trennt das Netzteil nie, um ein
        //    Limit zu halten: Das erzeugt nur zusätzliche Teilzyklen ohne belegten Nutzen.
        guard hasChargeControl else {
            return ControllerDecision(
                state: .disabled,
                chargingEnabled: true,
                adapterConnected: true,
                resetChargeToFullOnce: config.chargeToFullOnce && battery.percent >= 100,
                message: config.enabled ? Self.nativeLimitMessage : "Batterieschutz deaktiviert"
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

    /// Ladezustand für den Systemschlaf. Aktives Entladen endet vor dem Schlaf immer.
    /// Eine erreichte Ladegrenze bleibt über die SMC-Ladesperre gesperrt, sonst lädt der
    /// Mac im Schlaf bis 100 %. Unter der unteren Grenze darf er weiter laden: lieber über
    /// das Ziel als mit leerem Akku aufwachen. Alle Sonderfälle bleiben beim Normalbetrieb.
    public static func chargingEnabledDuringSleep(config: BGConfig, battery: BatteryInfo,
                                                  hasChargeControl: Bool, now: Date = Date()) -> Bool {
        guard hasChargeControl, config.mode == .auto,
              battery.percentAvailable, (0...100).contains(battery.percent) else { return true }
        let effective = config.effective(at: now)
        guard effective.enabled, !effective.chargeToFullOnce, effective.specialChargePlan == nil,
              effective.upperLimit < 100 else { return true }
        return battery.percent < effective.lowerLimit
    }

    /// Stabile Meldung; die App erkennt daran, dass macOS das Ladelimit hält.
    public static let nativeLimitMessage = "Keine separate Ladesperre – macOS-Ladelimit übernimmt (Systemeinstellungen → Batterie)"
}


public final class BatteryController: @unchecked Sendable {
    public let smc: SMCClient
    private var previousDecision: ControllerDecision?
    private var lastAppliedCharging: Bool?
    private var lastAppliedAdapter: Bool?
    private var lastAppliedMagSafeLED: SMCClient.MagSafeColor?
    private var lastHardwareCheckUptime: TimeInterval?
    private let lock = NSLock()
    public let nativeLimit: NativeChargeLimitDriving?
    private var lastAppliedNativeLimit: Int?
    /// Nach einem Fehlschlag nicht bei jedem Durchlauf erneut schreiben und warten.
    private var nativeRetryAfterUptime: TimeInterval?
    static let nativeRetryInterval: TimeInterval = 300
    /// Der vom Dienst gesetzte macOS-Ladelimitwert, solange er die Steuerung hält.
    public private(set) var nativeLimitControlled: Int?

    public init(smc: SMCClient = .shared, nativeLimit: NativeChargeLimitDriving? = nil) {
        self.smc = smc
        self.nativeLimit = nativeLimit
    }

    /// Ohne SMC-Ladesperre übernimmt das macOS-Ladelimit die Rolle der Sperre, wenn der Nutzer
    /// das erlaubt hat. Pause, ausgeschalteter Schutz und der macOS-Modus geben es zurück.
    private func usesNativeLimit(config: BGConfig, battery: BatteryInfo, now: Date) -> Bool {
        guard let nativeLimit, !smc.hasChargeControl, config.controlsNativeLimit, config.mode == .auto,
              battery.percentAvailable, config.effective(at: now).enabled else { return false }
        return nativeLimit.isSupported
    }

    public func step(
        config: BGConfig,
        battery: BatteryInfo,
        dryRun: Bool,
        desktop: DesktopEnvironment.Snapshot? = nil,
        logger: ((String) -> Void)? = nil
    ) -> ControllerDecision {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let native = usesNativeLimit(config: config, battery: battery, now: now)
        let uptime = ProcessInfo.processInfo.systemUptime
        if !dryRun && (lastHardwareCheckUptime.map { uptime - $0 >= 60 } ?? true) {
            lastHardwareCheckUptime = uptime
            if native, let expected = lastAppliedNativeLimit, nativeLimit?.currentLimit() != expected {
                // Etwa nach einer Änderung in den Systemeinstellungen: Ziel erneut setzen.
                lastAppliedNativeLimit = nil
                logger?("macOS-Ladelimit weicht ab – B-Guard setzt \(expected) % erneut.")
            }
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
            hasChargeControl: smc.hasChargeControl || native,
            // Bei aktivem macOS-Limit ignoriert macOS den Netzteil-Schalter; entladen wird über das Limit.
            hasDischargeControl: smc.hasDischargeControl && !native,
            allowsAdapterDisconnect: (desktop ?? DesktopEnvironment.snapshot()).allowsAdapterDisconnect,
            now: now
        )

        var controlFailed = false
        var nativeFailed = false
        if native {
            // Ohne Netzteil gibt es nichts zu begrenzen; erst beim Anstecken zählt der neue Stand.
            if battery.pluggedIn {
                let ceiling = ControllerLogic.nativeCeiling(decision: decision, config: config, battery: battery,
                                                            allowBelow80: config.nativeLimitBelow80, now: now)
                if ceiling != lastAppliedNativeLimit, nativeRetryAfterUptime.map({ uptime >= $0 }) ?? true {
                    if dryRun {
                        logger?("[DRY-RUN] Würde das macOS-Ladelimit auf \(ceiling) % setzen")
                        lastAppliedNativeLimit = ceiling
                    } else if nativeLimit?.apply(ceiling) == true {
                        logger?("macOS-Ladelimit auf \(ceiling) % gesetzt.")
                        lastAppliedNativeLimit = ceiling
                        nativeRetryAfterUptime = nil
                    } else {
                        logger?("macOS-Ladelimit konnte nicht auf \(ceiling) % gesetzt werden.")
                        lastAppliedNativeLimit = nil
                        nativeRetryAfterUptime = uptime + Self.nativeRetryInterval
                    }
                }
                nativeFailed = nativeRetryAfterUptime.map { uptime < $0 } ?? false
            }
            nativeLimitControlled = nativeFailed ? nil : lastAppliedNativeLimit
        } else {
            if !dryRun, nativeLimit?.hasTakenControl == true {
                let restored = nativeLimit?.release() ?? false
                logger?(restored ? "macOS-Ladelimit an macOS zurückgegeben."
                                 : "macOS-Ladelimit konnte nicht zurückgegeben werden.")
            }
            lastAppliedNativeLimit = nil
            nativeLimitControlled = nil
        }

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

        if nativeFailed {
            return ControllerDecision(state: .unsupported, chargingEnabled: true, adapterConnected: true,
                message: "macOS-Ladelimit konnte nicht gesetzt werden – macOS lädt nach seinen eigenen Einstellungen")
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

    /// Vor dem Schlaf: Netzteil immer verbinden und die Ladesperre nur halten, wenn
    /// `chargingEnabled` false ist. Scheitert das Verbinden, wird alles normalisiert.
    public func prepareForSleep(chargingEnabled: Bool, logger: ((String) -> Void)? = nil) {
        guard !chargingEnabled, smc.hasChargeControl else {
            restoreNormal(logger: logger)
            return
        }
        lock.lock()
        defer { lock.unlock() }

        let adapter = !smc.hasDischargeControl || smc.setAdapterConnected(true)
        guard adapter else {
            // Nie mit getrenntem Netzteil schlafen: lieber vollständig normalisieren.
            let restored = smc.restoreNormal()
            logger?(restored ? "SMC: Netzteil vor dem Schlaf über Normalbetrieb verbunden."
                             : "SMC: Netzteil konnte vor dem Schlaf nicht verbunden werden.")
            invalidateLocked()
            return
        }
        let inhibited = smc.setChargingEnabled(false)
        let led = !smc.keyExists("ACLC") || smc.setMagSafeLED(.auto)
        previousDecision = nil
        lastAppliedAdapter = true
        lastAppliedCharging = inhibited ? false : nil
        lastAppliedMagSafeLED = led ? .auto : nil
        lastHardwareCheckUptime = nil
        logger?(inhibited ? "SMC: Netzteil verbunden, Ladegrenze bleibt im Schlaf gesperrt."
                          : "SMC: Ladesperre vor dem Schlaf fehlgeschlagen – macOS steuert das Laden.")
    }

    private func invalidateLocked() {
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
