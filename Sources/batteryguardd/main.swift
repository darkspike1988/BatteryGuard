import Foundation
import BatteryGuardShared
import IOKit.ps
import IOKit.pwr_mgt
import CoreGraphics

final class DaemonRunner: @unchecked Sendable {
    private let controller: BatteryController
    private let dryRun: Bool
    private let isOnce: Bool
    private var detectedSMCKeys: [String] = []
    private var sleeping = false
    private var powerConnection: io_connect_t = 0
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private let configServer = ConfigServer()
    private let wakeUntilLimit = WakeUntilLimitGuard()
    private var configurationNotice: String?

    public init(controller: BatteryController = BatteryController(), dryRun: Bool = false, isOnce: Bool = false) {
        self.controller = controller
        self.dryRun = dryRun
        self.isOnce = isOnce
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private func log(_ message: String) {
        if !isOnce {
            print("[\(timestamp())] [batteryguardd] \(message)")
            fflush(stdout)
        }
    }

    private func logStderr(_ message: String) {
        fputs("[\(timestamp())] [batteryguardd] \(message)\n", stderr)
        fflush(stderr)
    }

    func ensureEnvironment() {
        guard !dryRun else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: BGPaths.directory) {
            do {
                try fm.createDirectory(atPath: BGPaths.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
                chmod(BGPaths.directory, 0o755)
                log("Verzeichnis \(BGPaths.directory) erstellt (0755).")
            } catch {
                if !isOnce {
                    logStderr("Hinweis: Konnte Verzeichnis \(BGPaths.directory) nicht anlegen: \(error.localizedDescription)")
                }
            }
        }

        if !fm.fileExists(atPath: BGPaths.config) {
            let defaultConfig = BGConfig().sanitized()
            if let data = try? BGJSON.encoder().encode(defaultConfig) {
                do {
                    try data.write(to: URL(fileURLWithPath: BGPaths.config), options: .atomic)
                    chmod(BGPaths.config, 0o644)
                    log("Standardkonfiguration \(BGPaths.config) angelegt (0644).")
                } catch {
                    if !isOnce {
                        logStderr("Hinweis: Konnte Konfigurationsdatei \(BGPaths.config) nicht schreiben: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func loadConfig() -> BGConfig {
        do { return try BGConfigFile.read(at: URL(fileURLWithPath: BGPaths.config)) }
        catch is DecodingError {
            if !dryRun {
                do {
                    let recovery = try BGConfigRecovery.prepare()
                    configurationNotice = recovery.message
                    if let message = recovery.message { log(message) }
                    return try BGConfigFile.read(at: URL(fileURLWithPath: BGPaths.config))
                } catch { logStderr("Einstellungen konnten nicht wiederhergestellt werden: \(error.localizedDescription)") }
            }
        } catch { logStderr("Einstellungen nicht lesbar: \(error.localizedDescription)") }
            var fallback = BGConfig()
            fallback.enabled = false
            return fallback.sanitized()
    }

    func writeStatus(_ status: BGStatus) {
        guard !dryRun else { return }
        guard let data = try? BGJSON.encoder().encode(status) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: BGPaths.status), options: .atomic)
            chmod(BGPaths.status, 0o644)
        } catch {
            if !isOnce {
                logStderr("Hinweis: Konnte status.json nicht schreiben: \(error.localizedDescription)")
            }
        }
    }

    func resetChargeToFullOnceInConfig(snapshot: BGConfig, at now: Date) {
        guard !dryRun else { return }
        do {
            try BGConfigFile.update(at: URL(fileURLWithPath: BGPaths.config)) { cfg in
                cfg = BGChargeCompletion.applying(snapshot: snapshot, to: cfg, at: now)
            }
            log("Volllade-Anforderung zurückgesetzt.")
        } catch {
            logStderr("Volllade-Anforderung konnte nicht zurückgesetzt werden: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func tick() -> BGStatus {
        guard !sleeping else { return BGStatus() }
        if !dryRun {
            do {
                let url = URL(fileURLWithPath: BGPaths.config)
                let snapshot = try BGConfigFile.read(at: url)
                if ScheduleRunner.needsEvaluation(config: snapshot, now: Date()) {
                    try BGConfigFile.update(at: url) { latest in
                        latest = ScheduleRunner.evaluate(config: latest, now: Date(),
                            context: ConfigServer.currentSpecialContext())
                    }
                }
            } catch { logStderr("Zeitplan konnte nicht ausgewertet werden: \(error.localizedDescription)") }
        }
        let storedConfig = loadConfig()
        let now = Date()
        let config = storedConfig
        let battery = BatteryReader.read(smcClient: controller.smc)

        let decision = controller.step(
            config: config,
            battery: battery,
            dryRun: dryRun,
            logger: { [weak self] msg in
                self?.log(msg)
            }
        )

        if !dryRun {
            wakeUntilLimit.reconcile(config: config, battery: battery, now: now,
                controlSupported: controller.smc.hasChargeControl && decision.state != .unsupported)
        }

        if !dryRun, let snapshot = storedConfig.calibrationPlan,
           decision.completedCalibrationRequestID != nil || (decision.updatedCalibrationPlan != nil && decision.updatedCalibrationPlan != snapshot) {
            do {
                try BGConfigFile.update(at: URL(fileURLWithPath: BGPaths.config)) { latest in
                    CalibrationControllerPersistence.apply(snapshot: snapshot, decision: decision, to: &latest)
                }
            } catch { logStderr("Kalibrierung konnte nicht aktualisiert werden: \(error.localizedDescription)") }
        }

        if !dryRun, let snapshot = storedConfig.specialChargePlan,
           decision.completedSpecialRequestID != nil || decision.updatedSpecialPlan != nil {
            do {
                try BGConfigFile.update(at: URL(fileURLWithPath: BGPaths.config)) { latest in
                    SpecialControllerPersistence.apply(snapshot: snapshot, decision: decision, to: &latest)
                }
            } catch { logStderr("Sonderaktion konnte nicht aktualisiert werden: \(error.localizedDescription)") }
        }

        if decision.resetChargeToFullOnce {
            resetChargeToFullOnceInConfig(snapshot: storedConfig, at: now)
        }

        var status = BGStatus()
        status.measurements = battery.measurements
        status.nativeChargeLimit = controller.smc.readNativeChargeLimit()
        status.percent = battery.percent
        status.percentAvailable = battery.percentAvailable
        status.externalPowerAvailable = battery.externalPowerAvailable
        status.awakeUntilLimitActive = wakeUntilLimit.isActive
        status.pluggedIn = battery.pluggedIn
        status.isChargingHardware = battery.isCharging
        status.state = decision.state
        status.temperatureCelsius = battery.temperatureCelsius
        status.cycleCount = battery.cycleCount
        status.healthPercent = battery.healthPercent
        status.watts = battery.watts
        status.voltage = battery.voltage
        status.amperage = battery.amperage
        status.timeRemainingMinutes = battery.timeRemainingMinutes
        status.maxCapacityMah = battery.maxCapacityMah
        status.designCapacityMah = battery.designCapacityMah
        status.smcKeysDetected = detectedSMCKeys
        status.daemonVersion = "0.4.0"
        status.updatedAt = Date()
        status.configurationNotice = configurationNotice
        status.message = storedConfig.isPaused(at: now) && decision.state != .unsupported
            ? "Schutz pausiert bis " + (storedConfig.pauseUntil?.formatted(date: .omitted, time: .shortened) ?? "")
            : decision.message

        if let wakeError = wakeUntilLimit.message {
            status.message = [status.message, wakeError].compactMap { $0 }.joined(separator: " · ")
        }

        writeStatus(status)
        return status
    }

    func runOnce() {
        defer { wakeUntilLimit.release() }
        ensureEnvironment()


        detectedSMCKeys = controller.smc.detectSupportedKeys()
        let status = tick()

        if let data = try? BGJSON.encoder().encode(status),
           let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    }

    private func registerSleepWakeNotifications() {
        let callback: IOServiceInterestCallback = { context, _, message, argument in
            guard let context else { return }
            let runner = Unmanaged<DaemonRunner>.fromOpaque(context).takeUnretainedValue()
            switch message {
            case 0xe0000270 /* kIOMessageCanSystemSleep, IOMessage.h */:
                IOAllowPowerChange(runner.powerConnection, Int(bitPattern: argument))
            case 0xe0000280 /* kIOMessageSystemWillSleep */:
                runner.sleeping = true
                runner.wakeUntilLimit.release()
                if !runner.dryRun { runner.controller.restoreNormal(logger: { runner.log($0) }) }
                runner.log("Schlafmodus: Normalbetrieb wiederhergestellt, Steuerung pausiert.")
                IOAllowPowerChange(runner.powerConnection, Int(bitPattern: argument))
            case 0xe0000300 /* kIOMessageSystemHasPoweredOn */:
                // Firmware may have changed SMC registers while asleep. Forget all cached writes.
                runner.controller.invalidateHardwareCache()
                runner.sleeping = false
                runner.log("Aufgewacht: Konfiguration und Hardware werden neu geprüft.")
                runner.tick()
            default: break
            }
        }
        powerConnection = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(),
                                                   &powerPort, callback, &powerNotifier)
        if powerConnection != 0, let port = powerPort,
           let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            log("Schlaf-/Aufwachbenachrichtigungen registriert.")
        } else {
            logStderr("Schlaf-/Aufwachbenachrichtigungen konnten nicht registriert werden.")
        }
    }

    private func registerDisplayNotifications() {
        let callback: CGDisplayReconfigurationCallBack = { _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            let runner = Unmanaged<DaemonRunner>.fromOpaque(context).takeUnretainedValue()
            // CoreGraphics may call from another thread. Serialize with power events
            // and timer ticks, and query displays after reconfiguration has completed.
            DispatchQueue.main.async { [weak runner] in
                guard let runner else { return }
                runner.log("Monitor-Konfiguration geändert – prüfe Netzteil-/Deckelschutz.")
                runner.tick()
            }
        }
        let result = CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())
        if result == .success {
            log("Monitor-Benachrichtigungen registriert.")
        } else {
            logStderr("Monitor-Benachrichtigungen nicht verfügbar; regelmäßige Prüfung bleibt aktiv.")
        }
    }

    func startDaemon() {
        log("batteryguardd gestartet (dryRun: \(dryRun)).")
        ensureEnvironment()

        if !dryRun {
            do {
                let recovery = try BGConfigRecovery.prepare()
                configurationNotice = recovery.message
                if let message = recovery.message { log(message) }
                try configServer.start()
                log("Sicherer Einstellungsdienst registriert.")
            } catch {
                configurationNotice = "Einstellungsdienst nicht verfügbar. Bitte den Dienst aktualisieren oder neu einrichten."
                logStderr(configurationNotice! + " " + error.localizedDescription)
            }
        }

        detectedSMCKeys = controller.smc.detectSupportedKeys()
        log("Erkannte SMC-Schlüssel: \(detectedSMCKeys.isEmpty ? "keine" : detectedSMCKeys.joined(separator: ", "))")
        if !controller.smc.hasChargeControl {
            log(controller.smc.hasDischargeControl
                ? "SMC-Ladesperre nicht vorhanden – Pendelsteuerung verfügbar."
                : "WARNUNG: Keine unterstützte Ladesteuerung vorhanden.")
        }

        // Failsafe bei SIGTERM / SIGINT: Normalbetrieb wiederherstellen
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler { [weak self] in
            guard let self = self else { exit(0) }
            self.log("SIGTERM empfangen - Failsafe: Normalbetrieb wird wiederhergestellt...")
            self.configServer.stop()
            self.wakeUntilLimit.release()
            if !self.dryRun { self.controller.restoreNormal(logger: { self.log($0) }) }
            exit(0)
        }
        signal(SIGTERM, SIG_IGN)
        sigtermSource.resume()

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler { [weak self] in
            guard let self = self else { exit(0) }
            self.log("SIGINT empfangen - Failsafe: Normalbetrieb wird wiederhergestellt...")
            self.configServer.stop()
            self.wakeUntilLimit.release()
            if !self.dryRun { self.controller.restoreNormal(logger: { self.log($0) }) }
            exit(0)
        }
        signal(SIGINT, SIG_IGN)
        sigintSource.resume()

        registerSleepWakeNotifications()
        registerDisplayNotifications()

        // Initialer Tick
        tick()

        // Timer alle 20 Sekunden
        let timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer, forMode: .default)

        // Sofortige Reaktion auf Netzteil-/Akku-Änderung via IOPSNotificationCreateRunLoopSource
        let powerCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
            guard let context = context else { return }
            let runner = Unmanaged<DaemonRunner>.fromOpaque(context).takeUnretainedValue()
            runner.log("Stromquellen-Änderung erkannt - führe sofortigen Tick aus.")
            runner.tick()
        }

        if let runLoopSource = IOPSNotificationCreateRunLoopSource(
            powerCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            log("IOPS-Benachrichtigungen erfolgreich registriert.")
        }

        RunLoop.current.run()
    }
}

// MARK: - Entry Point

let args = ProcessInfo.processInfo.arguments

if args.contains("--check-config-service") {
    do {
        _ = try BGConfigClient.read()
        print("Sicherer Einstellungsdienst erreichbar; Benutzerprüfung erfolgreich.")
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if args.contains("--dump-keys") {
    // Diagnose: alle (oder per Präfix gefilterte) SMC-Keys ausgeben, nur lesend.
    let prefixes = args.drop(while: { $0 != "--dump-keys" }).dropFirst().filter { !$0.hasPrefix("--") }
    let smc = SMCClient.shared
    guard smc.open() else { print("AppleSMC nicht erreichbar"); exit(1) }
    for k in smc.listAllKeys(prefixes: Array(prefixes)) {
        let hex = k.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("\(k.key)  \(k.type)  \(k.size)  [\(hex)]")
    }
    exit(0)
} else if args.contains("--once") {

    let runner = DaemonRunner(dryRun: true, isOnce: true)
    runner.runOnce()
    exit(0)
} else if args.contains("--restore") {
    let smc = SMCClient.shared
    _ = smc.open()
    let restored = smc.restoreNormal()
    guard restored else {
        fputs("Normalbetrieb konnte nicht vollständig wiederhergestellt werden.\n", stderr)
        exit(1)
    }
    let iso = ISO8601DateFormatter().string(from: Date())
    print("[\(iso)] [batteryguardd] Normalbetrieb wiederhergestellt (Laden an, Adapter an).")
    exit(0)
} else {
    let dryRun = args.contains("--dry-run")
    guard dryRun || geteuid() == 0 else {
        fputs("Der Hintergrunddienst benötigt Root-Rechte. Für lesende Diagnose --once verwenden.\n", stderr)
        exit(1)
    }
    let runner = DaemonRunner(dryRun: dryRun, isOnce: false)
    runner.startDaemon()
}
