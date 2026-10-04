import Foundation
import UserNotifications
import BatteryGuardShared

@MainActor
final class NotificationManager: Sendable {
    static let shared = NotificationManager()
    
    private var didNotifyLowerLimit: Bool = false
    private var didNotifyUpperLimit: Bool = false
    private var didNotifyHeat: Bool = false
    
    private init() {}
    
    func checkNotifications(status: BGStatus, config: BGConfig) {
        // UNUserNotificationCenter nur verwenden, wenn Bundle-ID vorhanden, sonst still ignorieren
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        let preferences = UserDefaults.standard
        let lowEnabled = preferences.object(forKey: "bg.notifyLow") as? Bool ?? true
        let limitEnabled = preferences.object(forKey: "bg.notifyLimit") as? Bool ?? false
        let heatEnabled = preferences.object(forKey: "bg.notifyHeat") as? Bool ?? true
        let config = config.effective(at: Date())
        if let temperature = status.temperatureCelsius {
            let threshold = Double(config.heatProtectionCelsius > 0 ? config.heatProtectionCelsius : 40)
            if temperature > threshold, heatEnabled, !didNotifyHeat {
                didNotifyHeat = true
                send(title: "Akku ist warm", body: String(format: "Aktuell %.1f °C. Prüfe Belüftung und Hitzeschutz.", temperature))
            } else if temperature < threshold - 2 { didNotifyHeat = false }
        }

        let onBattery = !status.pluggedIn || status.state == .onBattery
        
        // 1. Bei Akkubetrieb <= lowerLimit: 'Akku bei X % – bitte laden'
        if onBattery {
            if status.percent <= config.lowerLimit {
                if !didNotifyLowerLimit, lowEnabled {
                    didNotifyLowerLimit = true
                    send(
                        title: "B-Guard",
                        body: "Akku bei \(status.percent) % – bitte laden"
                    )
                }
            } else if status.percent > config.lowerLimit + 2 {
                didNotifyLowerLimit = false
            }
        } else {
            // Am Netzteil: Akkuwarnung zurücksetzen
            didNotifyLowerLimit = false
        }
        
        // 2. Beim Erreichen von upperLimit am Netzteil: 'Limit erreicht'
        if status.pluggedIn {
            let reachedUpper = config.enabled && config.mode != .native && config.mode != .direct && !config.chargeToFullOnce && status.percent >= config.upperLimit
            if reachedUpper {
                if !didNotifyUpperLimit, limitEnabled {
                    didNotifyUpperLimit = true
                    send(
                        title: "B-Guard",
                        body: "Limit erreicht"
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
