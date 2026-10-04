import Foundation
import BatteryGuardShared
import IOKit.ps

final class DaemonRunner: @unchecked Sendable {
    private let controller: BatteryController
    private let dryRun: Bool
    private let isOnce: Bool
    private var detectedSMCKeys: [String] = []

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
                    chmod(BGPaths.config, 0o666)
                    log("Standardkonfiguration \(BGPaths.config) angelegt (0666).")
                } catch {
                    if !isOnce {
                        logStderr("Hinweis: Konnte Konfigurationsdatei \(BGPaths.config) nicht schreiben: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func loadConfig() -> BGConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: BGPaths.config)),
              let decoded = try? BGJSON.decoder().decode(BGConfig.self, from: data) else {
            var fallback = BGConfig()
            fallback.enabled = false
            return fallback.sanitized()
        }
        return decoded.sanitized()
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

    func resetChargeToFullOnceInConfig() {
        guard !dryRun else { return }
        var cfg = loadConfig()
        cfg.chargeToFullOnce = false
        cfg.fullChargeUntil = nil
        if cfg.isTravelCharging(at: Date()) { cfg.travelReadyAt = nil }
        if let data = try? BGJSON.encoder().encode(cfg) {
            do {
                try data.write(to: URL(fileURLWithPath: BGPaths.config), options: .atomic)
                chmod(BGPaths.config, 0o666)
                log("chargeToFullOnce erfolgreich im Config-File auf false zurückgesetzt.")
            } catch {
                logStderr("Fehler beim Zurücksetzen von chargeToFullOnce in \(BGPaths.config): \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func tick() -> BGStatus {
        let storedConfig = loadConfig()
        let now = Date()
        let config = storedConfig.effective(at: now)
        let battery = BatteryReader.read(smcClient: controller.smc)

        let decision = controller.step(
            config: config,
            battery: battery,
            dryRun: dryRun,
            logger: { [weak self] msg in
                self?.log(msg)
            }
        )

        if decision.resetChargeToFullOnce {
            resetChargeToFullOnceInConfig()
        }

        var status = BGStatus()
        status.nativeChargeLimit = controller.smc.readNativeChargeLimit()
        status.percent = battery.percent
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
        status.daemonVersion = "0.2.0"
        status.updatedAt = Date()
        status.message = storedConfig.isPaused(at: now) && decision.state != .unsupported
            ? "Schutz pausiert bis " + (storedConfig.pauseUntil?.formatted(date: .omitted, time: .shortened) ?? "")
            : decision.message

        writeStatus(status)
        return status
    }

    func runOnce() {
        ensureEnvironment()
        detectedSMCKeys = controller.smc.detectSupportedKeys()
        let status = tick()

        if let data = try? BGJSON.encoder().encode(status),
           let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    }

    func startDaemon() {
        log("batteryguardd gestartet (dryRun: \(dryRun)).")
        ensureEnvironment()

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
            if !self.dryRun { self.controller.restoreNormal(logger: { self.log($0) }) }
            exit(0)
        }
        signal(SIGTERM, SIG_IGN)
        sigtermSource.resume()

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler { [weak self] in
            guard let self = self else { exit(0) }
            self.log("SIGINT empfangen - Failsafe: Normalbetrieb wird wiederhergestellt...")
            if !self.dryRun { self.controller.restoreNormal(logger: { self.log($0) }) }
            exit(0)
        }
        signal(SIGINT, SIG_IGN)
        sigintSource.resume()

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

if args.contains("--dump-keys") {
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
    let runner = DaemonRunner(dryRun: dryRun, isOnce: false)
    runner.startDaemon()
}
