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
    
    var body: some View {
        HStack(spacing: 5) {
            // Einzigartiger, runder Ladering statt des Apple-Standard-Batterie-Icons
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                
                let fraction = CGFloat(min(max(status.percent, 0), 100)) / 100.0
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                // Icon im Inneren des Rings
                if status.state == .holding {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6, weight: .bold))
                } else if status.pluggedIn {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                } else {
                    // Im Akkubetrieb zeigen wir ein kleines Schild als "Guard"-Logo
                    Image(systemName: "shield.fill")
                        .font(.system(size: 6, weight: .regular))
                }
            }
            .frame(width: 14, height: 14)
            .padding(.trailing, 1)
            
            Text("\(status.percent) %")
                .monospacedDigit()
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }
}
