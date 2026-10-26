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
    /// Natives macOS-Ladelimit, das im macOS-Limit-Modus gesetzt werden soll (nil = nicht anfassen).
    public var systemChargeLimit: Int? = nil
    public var coldProtectionActive: Bool = false
    /// Tatsächlich angestrebter Ladestand im macOS-Limit-Modus (beim Halten unter der Mindeststufe das Profilziel).
    public var effectiveTargetPercent: Int? = nil

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
    public static let coldRecoveryMarginCelsius = 2.0

    /// Laden unter der Kälteschwelle sperren; Freigabe erst zwei Grad darüber.
    static func needsColdProtection(config: BGConfig, battery: BatteryInfo, previousDecision: ControllerDecision?) -> Bool {
        let wasActive = previousDecision?.coldProtectionActive == true
        guard config.coldProtectionCelsius > 0 else { return false }
        guard let temperature = battery.temperatureCelsius, temperature.isFinite else { return wasActive }
        let threshold = Double(config.coldProtectionCelsius)
        return wasActive ? temperature < threshold + coldRecoveryMarginCelsius : temperature < threshold
    }

    static func coldMessage(config: BGConfig, battery: BatteryInfo) -> String {
        guard let temperature = battery.temperatureCelsius, temperature.isFinite else {
            return "Kälteschutz bleibt aktiv – Temperatur momentan nicht verfügbar"
        }
        return "Kälteschutz aktiv: \(String(format: "%.1f", temperature))°C – Laden ab \(config.coldProtectionCelsius + Int(coldRecoveryMarginCelsius))°C"
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
        systemChargeLimits: [Int] = [],
        now: Date = Date()
    ) -> ControllerDecision {
        if config.mode == .systemLimit {
            return evaluateSystemLimit(config: config, battery: battery, previousDecision: previousDecision,
                                       available: systemChargeLimits, canHoldWithAdapterSwitch: hasDischargeControl && allowsAdapterDisconnect,
                                       now: now)
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

        if needsColdProtection(config: config, battery: battery, previousDecision: previousDecision) {
            var cold = ControllerDecision(state: .holding, chargingEnabled: false, adapterConnected: true,
                                          message: coldMessage(config: config, battery: battery))
            cold.coldProtectionActive = true
            return cold
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

    /// macOS-Limit-Modus: B-Guard wählt Apples natives Ladelimit; macOS bietet feste Stufen an, daher wird
    /// das Ziel auf die nächste Stufe aufgerundet. Mit `allowLimitsBelowSystemMinimum` hält der Netzteil-Schalter
    /// Ziele darunter (auf Firmware 20457 hält `CHIE = 08` das Laden an), die kleinste Stufe bleibt Sicherheitsnetz.
    static func evaluateSystemLimit(config: BGConfig, battery: BatteryInfo, previousDecision: ControllerDecision?,
                                    available: [Int], canHoldWithAdapterSwitch: Bool = false, now: Date) -> ControllerDecision {
        guard let maximum = available.max(), let minimum = available.min() else {
            return ControllerDecision(state: .unsupported, chargingEnabled: true, adapterConnected: true,
                message: "macOS-Limit auf diesem Mac nicht verfügbar – Normalbetrieb wiederhergestellt")
        }
        func decision(_ state: BGChargeState, limit: Int, message: String?, reset: Bool = false,
                      adapterConnected: Bool = true) -> ControllerDecision {
            var result = ControllerDecision(state: state, chargingEnabled: true, adapterConnected: adapterConnected,
                                            resetChargeToFullOnce: reset, message: message)
            result.systemChargeLimit = limit
            return result
        }
        // Ein selbst gehaltenes Netzteil meldet sich als „nicht angesteckt“.
        let plugged = battery.pluggedIn || previousDecision?.adapterConnected == false
        let canHold = canHoldWithAdapterSwitch && config.allowLimitsBelowSystemMinimum
        if let plan = config.specialChargePlan {
            let power: BGExternalPowerSource = battery.externalPowerAvailable ? (plugged ? .connected : .disconnected) : .unknown
            let outcome = plan.evaluate(context: BGSpecialPlanEvaluationContext(
                percent: battery.percentAvailable ? battery.percent : nil, externalPower: power,
                canBlockCharging: true, canDisconnectAdapter: true, allowsAdapterDisconnect: true), at: now)
            let running = config.enabled && !config.isPaused(at: now) && outcome.isActive
            if running && plan.kind == .topUp {
                if var protection = temperatureProtection(config: config, battery: battery, previousDecision: previousDecision,
                                                          minimum: minimum, plugged: plugged, canHold: canHoldWithAdapterSwitch) {
                    protection.updatedSpecialPlan = outcome.updatedPlan
                    return protection
                }
                var result = decision(battery.percent < 100 ? .charging : .holding, limit: maximum, message: outcome.reason)
                result.updatedSpecialPlan = outcome.updatedPlan
                return result
            }
            // Einmal entladen: Die Firmware entlädt am Netzteil bis zu einer angebotenen Stufe.
            if running && plan.kind == .discharge && available.contains(plan.targetPercent) {
                var result = decision(.discharging, limit: plan.targetPercent, message: outcome.reason)
                result.updatedSpecialPlan = outcome.updatedPlan
                return result
            }
            var result = ControllerDecision(state: outcome.isComplete ? .disabled : .unsupported,
                chargingEnabled: true, adapterConnected: true,
                message: [.topUp, .discharge].contains(plan.kind) ? outcome.reason : "Sonderaktion im macOS-Limit-Modus nicht verfügbar")
            result.completedSpecialRequestID = plan.requestID
            return result
        }
        guard config.enabled, !config.isPaused(at: now) else {
            return decision(.disabled, limit: maximum, message: config.enabled ? nil : "Batterieschutz deaktiviert",
                            reset: config.chargeToFullOnce && battery.percent >= 100)
        }
        let config = config.effective(at: now)
        let wanted = config.chargeToFullOnce ? 100 : config.upperLimit
        let limit = BGSystemChargeLimit.target(for: wanted, available: available) ?? maximum
        guard battery.percentAvailable else {
            return decision(.unsupported, limit: limit, message: "Ladestand nicht verfügbar – macOS-Limit bleibt bei \(limit) %")
        }
        if let protection = temperatureProtection(config: config, battery: battery, previousDecision: previousDecision,
                                                  minimum: minimum, plugged: plugged, canHold: canHoldWithAdapterSwitch) {
            return protection
        }
        let reset = config.chargeToFullOnce && battery.percent >= 100
        guard plugged else { return decision(.onBattery, limit: limit, message: nil, reset: reset) }
        if canHold && wanted < minimum {
            var holding = previousDecision?.adapterConnected == false
            if battery.percent >= wanted { holding = true } else if battery.percent < config.lowerLimit { holding = false }
            var result = holding
                ? decision(.holding, limit: minimum, message: "Ladelimit von \(wanted) % gehalten (Netzteil-Schalter, macOS-Limit \(minimum) %)",
                           adapterConnected: false)
                : decision(.charging, limit: minimum, message: "Laden aktiv bis \(wanted) % (Netzteil-Schalter)")
            result.effectiveTargetPercent = wanted
            return result
        }
        if battery.percent >= limit {
            return decision(.holding, limit: limit, message: "macOS-Limit von \(limit) % gehalten", reset: reset)
        }
        return decision(.charging, limit: limit, message: "Laden aktiv bis \(limit) % (macOS-Limit)")
    }

    public static let temperatureReservePercent = 20

    /// Hitze- und Kälteschutz im macOS-Limit-Modus. Aus Sicherheitsgründen hält der Netzteil-Schalter das Laden
    /// auch ohne Opt-in an; an der Akkureserve bleibt das Netzteil verbunden. Ohne Schalter sinkt nur das Limit.
    static func temperatureProtection(config: BGConfig, battery: BatteryInfo, previousDecision: ControllerDecision?,
                                      minimum: Int, plugged: Bool, canHold: Bool) -> ControllerDecision? {
        let heat = needsHeatProtection(config: config, battery: battery, previousDecision: previousDecision)
        let cold = !heat && needsColdProtection(config: config, battery: battery, previousDecision: previousDecision)
        guard heat || cold else { return nil }
        // Feste Reserve: Auf Firmware, die bei `CHIE = 08` doch entlädt, darf der Mac nicht leerlaufen.
        let reserveReached = battery.percent <= temperatureReservePercent
            || ((previousDecision?.heatProtectionActive == true || previousDecision?.coldProtectionActive == true)
                && previousDecision?.adapterConnected == true && previousDecision?.systemChargeLimit != nil)
        let hold = canHold && plugged && !reserveReached
        let base = heat ? heatMessage(battery: battery) : coldMessage(config: config, battery: battery)
        let suffix = hold ? "Laden über den Netzteil-Schalter angehalten"
            : (battery.percent < minimum ? "macOS-Limit \(minimum) %, darunter lädt macOS weiter" : "macOS-Limit vorübergehend \(minimum) %")
        var result = ControllerDecision(state: .holding, chargingEnabled: !hold, adapterConnected: !hold,
                                        message: base + " · " + suffix)
        result.systemChargeLimit = minimum
        result.effectiveTargetPercent = minimum
        result.heatProtectionActive = heat
        result.coldProtectionActive = cold
        if heat {
            result.heatProtectionThresholdCelsius = config.heatProtectionCelsius > 0
                ? config.heatProtectionCelsius : previousDecision?.heatProtectionThresholdCelsius
        }
        return result
    }

    /// Stabile Meldung; die App erkennt daran, dass macOS das Ladelimit hält.
    public static let nativeLimitMessage = "Keine separate Ladesperre – macOS-Ladelimit übernimmt (Systemeinstellungen → Batterie)"
}


/// Was vor dem Systemschlaf passiert. Standard bleibt die Freigabe auf Normalbetrieb.
public enum SleepChargePolicy: Equatable, Sendable {
    case release
    /// SMC-Ladesperre aktiv lassen; Netzteil bleibt verbunden.
    case inhibitCharging
    /// macOS-Limit auf die nächste Stufe über dem aktuellen Ladestand setzen.
    case systemLimit(Int)

    public static func decide(config: BGConfig, battery: BatteryInfo, hasChargeControl: Bool,
                              systemChargeLimits: [Int], now: Date = Date()) -> SleepChargePolicy {
        guard config.enabled, !config.isPaused(at: now),
              config.mode != .native, config.mode != .direct, battery.pluggedIn, battery.percentAvailable else { return .release }
        let effective = config.effective(at: now)
        // Vollladen, Reise und Top Up haben Vorrang: dann wie bisher freigeben.
        guard !effective.chargeToFullOnce, effective.specialChargePlan == nil else { return .release }
        if config.mode == .systemLimit {
            // Ohne Opt-in bleibt das gesetzte macOS-Limit im Schlaf ohnehin in der Firmware aktiv.
            guard config.stopChargingWhenSleeping,
                  let limit = BGSystemChargeLimit.target(for: max(battery.percent, 1), available: systemChargeLimits) else { return .release }
            return .systemLimit(limit)
        }
        guard hasChargeControl else { return .release }
        if config.stopChargingWhenSleeping { return .inhibitCharging }
        // Standard: Ein erreichtes Limit bleibt gesperrt, sonst lädt der Mac im Schlaf bis 100 %.
        // Unter der unteren Grenze darf er weiterladen: lieber über dem Ziel als leer aufwachen.
        return config.mode == .auto && effective.upperLimit < 100 && battery.percent >= effective.lowerLimit
            ? .inhibitCharging : .release
    }
}

public final class BatteryController: @unchecked Sendable {
    public let smc: SMCClient
    let systemLimit: SystemChargeLimitController
    private var previousDecision: ControllerDecision?
    private var lastAppliedCharging: Bool?
    private var lastAppliedAdapter: Bool?
    private var lastAppliedMagSafeLED: SMCClient.MagSafeColor?
    /// Fehlgeschlagenes LED-Ziel; erst bei neuem Ziel oder nach dem Aufwachen erneut versuchen.
    private var failedMagSafeLED: SMCClient.MagSafeColor?
    private var lastHardwareCheckUptime: TimeInterval?
    private let lock = NSLock()

    init(smc: SMCClient = .shared, systemLimit: SystemChargeLimitController = SystemChargeLimitController()) {
        self.smc = smc
        self.systemLimit = systemLimit
    }

    public convenience init(smc: SMCClient = .shared) {
        self.init(smc: smc, systemLimit: SystemChargeLimitController())
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

        var decision = ControllerLogic.evaluate(
            config: config,
            battery: battery,
            previousDecision: previousDecision,
            hasChargeControl: smc.hasChargeControl,
            hasDischargeControl: smc.hasDischargeControl,
            allowsAdapterDisconnect: (desktop ?? DesktopEnvironment.snapshot()).allowsAdapterDisconnect,
            systemChargeLimits: config.mode == .systemLimit ? systemLimit.availableLimits() : []
        )

        var controlFailed = false
        if config.mode != .systemLimit {
            systemLimit.restoreOriginal(dryRun: dryRun, logger: logger)
        }
        if let limit = decision.systemChargeLimit,
           !systemLimit.apply(limit, dryRun: dryRun, logger: logger) {
            // Nicht vorzeitig zurückkehren: ein gehaltenes Netzteil muss unten wieder verbunden werden.
            decision = ControllerDecision(state: .unsupported, chargingEnabled: true, adapterConnected: true,
                message: "macOS-Limit konnte nicht gesetzt werden – macOS behält das bisherige Limit")
        }

        // MagSafe LED bestimmen
        let targetLED: SMCClient.MagSafeColor
        if config.magsafeLedOff {
            targetLED = .off
        } else if !config.magsafeLed || !config.enabled {
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
            
            if smc.keyExists("ACLC") && targetLED != lastAppliedMagSafeLED && targetLED != failedMagSafeLED {
                let success = smc.setMagSafeLED(targetLED)
                logger?("SMC: setMagSafeLED(\(targetLED)) => \(success ? "ok" : "failed")")
                if success {
                    lastAppliedMagSafeLED = targetLED
                    failedMagSafeLED = nil
                } else {
                    // Die LED ist rein kosmetisch: kein Schreibversuch in jedem Regeltakt.
                    failedMagSafeLED = targetLED
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

    /// Vor dem Schlaf: Freigabe oder, falls gewünscht, Laden angehalten lassen.
    public func prepareForSleep(config: BGConfig, battery: BatteryInfo, dryRun: Bool, logger: ((String) -> Void)? = nil) {
        let policy = SleepChargePolicy.decide(config: config, battery: battery, hasChargeControl: smc.hasChargeControl,
            systemChargeLimits: config.mode == .systemLimit ? systemLimit.availableLimits() : [])
        switch policy {
        case .release:
            if !dryRun { restoreNormal(logger: logger) }
            logger?("Schlafmodus: Normalbetrieb wiederhergestellt, Steuerung pausiert.")
        case .inhibitCharging:
            guard !dryRun else { logger?("[DRY-RUN] Schlafmodus: Laden würde angehalten bleiben"); return }
            let held: Bool = {
                lock.lock(); defer { lock.unlock() }
                let charging = smc.setChargingEnabled(false)
                let adapter = !smc.hasDischargeControl || smc.setAdapterConnected(true)
                if smc.keyExists("ACLC") { smc.setMagSafeLED(.auto) }
                previousDecision = nil; lastAppliedCharging = nil; lastAppliedAdapter = nil; lastAppliedMagSafeLED = nil
                return charging && adapter
            }()
            if held {
                logger?("Schlafmodus: Laden bleibt angehalten, Netzteil verbunden.")
            } else {
                logger?("Schlafmodus: Laden konnte nicht angehalten werden.")
                restoreNormal(logger: logger)
            }
        case .systemLimit(let limit):
            let success = systemLimit.apply(limit, dryRun: dryRun, logger: logger)
            logger?(success ? "Schlafmodus: macOS-Limit auf \(limit) % gesetzt." : "Schlafmodus: macOS-Limit unverändert.")
        }
    }

    public func invalidateHardwareCache() {
        lock.lock()
        defer { lock.unlock() }
        previousDecision = nil
        lastAppliedCharging = nil
        lastAppliedAdapter = nil
        lastAppliedMagSafeLED = nil
        failedMagSafeLED = nil
        lastHardwareCheckUptime = nil
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
