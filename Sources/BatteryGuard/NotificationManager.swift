import Foundation
import UserNotifications
import BatteryGuardShared

@MainActor
final class NotificationManager: Sendable {
    static let shared = NotificationManager()
    
    private var lowBatteryPolicy = LowBatteryWarningPolicy()
    private var didNotifyUpperLimit: Bool = false
    private var didNotifyHeat: Bool = false

    private enum Key {
        static let lastFullCharge = "bg.lastFullChargeAt"
        static let lastCalibrationReminder = "bg.lastCalibrationReminderAt"
        static let lastWeeklyReport = "bg.lastWeeklyReportAt"
        static let lastHealthAlert = "bg.lastHealthAlertAt"
    }
    static let calibrationInterval: TimeInterval = 42 * 86400
    static let calibrationRepeat: TimeInterval = 14 * 86400
    static let weeklyInterval: TimeInterval = 7 * 86400

    private init() {}
    
    func checkNotifications(status: BGStatus, config: BGConfig) {
        // UNUserNotificationCenter nur verwenden, wenn Bundle-ID vorhanden, sonst still ignorieren
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        let preferences = UserDefaults.standard
        let lowEnabled = preferences.object(forKey: "bg.notifyLow") as? Bool ?? true
        let limitEnabled = preferences.object(forKey: "bg.notifyLimit") as? Bool ?? false
        let heatEnabled = preferences.object(forKey: "bg.notifyHeat") as? Bool ?? true
        let lowThreshold = LowBatteryWarningPolicy.threshold(from: preferences)
        let config = config.effective(at: Date())
        if let temperature = status.temperatureCelsius {
            let threshold = Double(config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : 40)
            if temperature > threshold, heatEnabled, !didNotifyHeat {
                didNotifyHeat = true
                send(title: L("Akku ist warm"), body: L("Aktuell %.1f °C. Prüfe Belüftung und Hitzeschutz.", temperature))
            } else if temperature < threshold - 2 { didNotifyHeat = false }
        }

        let calibrationEnabled = preferences.object(forKey: "bg.notifyCalibration") as? Bool ?? true
        if status.hasBatteryPercent {
            checkCalibration(status: status, enabled: calibrationEnabled, preferences: preferences)
        }

        let healthEnabled = preferences.object(forKey: "bg.notifyHealth") as? Bool ?? true
        checkBatteryHealth(status: status, enabled: healthEnabled, preferences: preferences)

        guard status.hasBatteryPercent && status.hasExternalPower else { return }
        let onBattery = !status.pluggedIn || status.state == .onBattery
        
        // 1. Bei Akkubetrieb <= lowBatteryThreshold: 'Akku bei X % – bitte laden'
        if lowBatteryPolicy.evaluate(
            percent: status.percent,
            onBattery: onBattery,
            threshold: lowThreshold,
            enabled: lowEnabled
        ) {
            send(
                title: "B-Guard",
                body: L("Akku bei %lld %% – bitte laden", status.percent)
            )
        }
        
        // 2. Beim Erreichen von upperLimit am Netzteil: 'Limit erreicht'
        if status.pluggedIn {
            let reachedUpper = config.enabled && config.mode != .native && config.mode != .direct && !config.chargeToFullOnce && status.percent >= config.upperLimit
            if reachedUpper {
                if !didNotifyUpperLimit, limitEnabled {
                    didNotifyUpperLimit = true
                    send(
                        title: "B-Guard",
                        body: L("Limit erreicht")
                    )
                }
            } else if status.percent < config.upperLimit - 2 {
                didNotifyUpperLimit = false
            }
        } else {
            // Netzteil getrennt: Limit-Warnung zurücksetzen
            didNotifyUpperLimit = false
        }
    }
    
    private func checkCalibration(status: BGStatus, enabled: Bool, preferences: UserDefaults) {
        let now = Date()
        guard let lastFull = preferences.object(forKey: Key.lastFullCharge) as? Date else {
            preferences.set(now, forKey: Key.lastFullCharge)
            return
        }
        if status.percent >= 99, status.pluggedIn {
            // Minutengenau reicht: nicht bei jeder Statusabfrage in UserDefaults schreiben.
            if now.timeIntervalSince(lastFull) >= 60 { preferences.set(now, forKey: Key.lastFullCharge) }
            return
        }
        guard enabled, now.timeIntervalSince(lastFull) >= Self.calibrationInterval else { return }
        let lastReminder = preferences.object(forKey: Key.lastCalibrationReminder) as? Date ?? .distantPast
        guard now.timeIntervalSince(lastReminder) >= Self.calibrationRepeat else { return }
        preferences.set(now, forKey: Key.lastCalibrationReminder)
        send(title: L("Zeit für eine Vollladung"),
             body: L("Seit %lld Wochen wurde keine Vollladung beobachtet. Eine gelegentliche Vollladung kann die Ladestandsschätzung unterstützen. B-Guard startet sie nicht automatisch.", Int(now.timeIntervalSince(lastFull) / (7 * 86400))))
    }

    private func checkBatteryHealth(status: BGStatus, enabled: Bool, preferences: UserDefaults) {
        guard let health = status.healthPercent else { return }
        let threshold = BatteryHealthAlertPolicy.threshold(from: preferences)
        if health >= threshold {
            if preferences.object(forKey: Key.lastHealthAlert) != nil {
                preferences.removeObject(forKey: Key.lastHealthAlert)
            }
            return
        }
        guard enabled else { return }
        let last = preferences.object(forKey: Key.lastHealthAlert) as? Date
        guard BatteryHealthAlertPolicy.shouldNotify(healthPercent: health, threshold: threshold,
                                                    lastSent: last, now: Date()) else { return }
        preferences.set(Date(), forKey: Key.lastHealthAlert)
        send(title: L("Akku wartungsbedürftig"),
             body: L("Die geschätzte Akkukapazität liegt bei %lld %% (Grenze %lld %%). Ein Akkutausch oder eine Wartung kann sinnvoll sein. Das ist keine Hardwarediagnose.",
                     health, threshold))
    }

    func checkWeeklyReport(samples: [BGHistorySample]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let preferences = UserDefaults.standard
        guard preferences.object(forKey: "bg.notifyWeekly") as? Bool ?? false else { return }
        let now = Date()
        guard let last = preferences.object(forKey: Key.lastWeeklyReport) as? Date else {
            preferences.set(now, forKey: Key.lastWeeklyReport)
            return
        }
        guard now.timeIntervalSince(last) >= Self.weeklyInterval else { return }
        let report = BGHistory.weeklyReport(samples, now: now)
        guard report.sampleCount >= 60 else { return }
        preferences.set(now, forKey: Key.lastWeeklyReport)
        let hours = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"),
                           report.summary.observedSeconds / 3600)
        let high = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"),
                          report.summary.highChargeSeconds / 3600)
        let hot = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"),
                         report.summary.hotSeconds / 3600)
        send(title: L("Dein Wochenbericht"),
             body: L("Aufgezeichnet: %@ h · ab 90 %%: %@ h · ab 40 °C: %@ h · Volllade-Tage: %lld",
                     hours, high, hot, report.fullChargeDays))
    }

    func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification dispatch error: \(error.localizedDescription)")
            }
        }
    }
}
