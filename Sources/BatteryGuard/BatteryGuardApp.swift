import SwiftUI
import AppKit
import BatteryGuardShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresence.shared.applyOnLaunch()
    }
}

@main
struct BatteryGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var statusStore: StatusStore
    @State private var configStore: ConfigStore
    
    init() {
        let config = ConfigStore()
        let status = StatusStore()
        status.configProvider = { [weak config] in
            config?.config ?? BGConfig()
        }
        _configStore = State(wrappedValue: config)
        _statusStore = State(wrappedValue: status)
    }
    
    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(
                statusStore: statusStore,
                configStore: configStore
            )
        } label: {
            MenuBarLabelView(
                status: statusStore.status,
                isDaemonActive: statusStore.isDaemonActive
            )
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    let status: BGStatus
    let isDaemonActive: Bool
    
    var iconName: String {
        if status.state == .holding {
            return "pause.circle"
        }
        
        let isCharging = status.pluggedIn && (status.state == .charging || status.isChargingHardware)
        let percent = min(max(status.percent, 0), 100)
        
        let level: String
        switch percent {
        case ..<13: level = "0percent"
        case 13..<38: level = "25percent"
        case 38..<63: level = "50percent"
        case 63..<88: level = "75percent"
        default: level = "100percent"
        }
        
        if isCharging {
            return "battery.\(level).bolt"
        } else {
            return "battery.\(level)"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text("\(status.percent) %")
                .monospacedDigit()
        }
    }
}
