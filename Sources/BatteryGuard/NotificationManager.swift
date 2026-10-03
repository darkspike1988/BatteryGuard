import Foundation
import UserNotifications
import BatteryGuardShared

@MainActor
final class NotificationManager: Sendable {
    static let shared = NotificationManager()
    
    private var didNotifyLowerLimit: Bool = false
    private var didNotifyUpperLimit: Bool = false
    private var hasRequestedAuthorization: Bool = false
    
    private init() {}
    
    func checkNotifications(status: BGStatus, config: BGConfig) {
        // UNUserNotificationCenter nur verwenden, wenn Bundle-ID vorhanden, sonst still ignorieren
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        if !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        
        let onBattery = !status.pluggedIn || status.state == .onBattery
        
        // 1. Bei Akkubetrieb <= lowerLimit: 'Akku bei X % – bitte laden'
        if onBattery {
            if status.percent <= config.lowerLimit {
                if !didNotifyLowerLimit {
                    didNotifyLowerLimit = true
                    send(
                        title: "BatteryGuard",
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
            let reachedUpper = status.percent >= config.upperLimit || status.state == .holding
            if reachedUpper {
                if !didNotifyUpperLimit {
                    didNotifyUpperLimit = true
                    send(
                        title: "BatteryGuard",
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
