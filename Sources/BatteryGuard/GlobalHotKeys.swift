import AppKit
import Carbon.HIToolbox
import BatteryGuardShared

/// Globale Tastenkürzel ⌃⌥⌘F (Vollladen), ⌃⌥⌘P (Pause/Fortsetzen), ⌃⌥⌘L (Low Power Mode).
/// Carbon-Hotkeys benötigen keine Bedienungshilfe-Freigabe; die Aktionen laufen über `bguard://`.
@MainActor
final class GlobalHotKeys {
    static let appStorageKey = "bg.globalHotKeys"
    static let shared = GlobalHotKeys()

    enum Command: UInt32, CaseIterable {
        case fullCharge = 1, togglePause, toggleLowPower

        var keyCode: UInt32 {
            switch self {
            case .fullCharge: UInt32(kVK_ANSI_F)
            case .togglePause: UInt32(kVK_ANSI_P)
            case .toggleLowPower: UInt32(kVK_ANSI_L)
            }
        }

        var title: String {
            switch self {
            case .fullCharge: L("⌃⌥⌘F · Einmal voll laden")
            case .togglePause: L("⌃⌥⌘P · Schutz pausieren oder fortsetzen")
            case .toggleLowPower: L("⌃⌥⌘L · Low Power Mode immer an oder aus")
            }
        }

        /// Befehl abhängig vom aktuellen Zustand.
        func url(config: BGConfig, now: Date = Date()) -> URL {
            switch self {
            case .fullCharge:
                return URL(string: config.chargeToFullOnce ? "bguard://cancel-full-charge" : "bguard://full-charge")!
            case .togglePause:
                return URL(string: config.isPaused(at: now) ? "bguard://resume" : "bguard://pause?minutes=60")!
            case .toggleLowPower:
                return URL(string: "bguard://power-mode?low=\(config.lowPowerModeRule == .always ? "off" : "always")")!
            }
        }
    }

    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func update(enabled: Bool) {
        unregister()
        guard enabled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let id = identifier.id
            Task { @MainActor in GlobalHotKeys.shared.perform(id) }
            return noErr
        }, 1, &eventType, nil, &handler)
        for command in Command.allCases {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: OSType(0x4247_4B59), id: command.rawValue) // „BGKY“
            if RegisterEventHotKey(command.keyCode, UInt32(controlKey | optionKey | cmdKey), identifier,
                                   GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                references.append(reference)
            }
        }
    }

    private func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func perform(_ id: UInt32) {
        guard let command = Command(rawValue: id), let store = AppDelegate.configStore else { return }
        AppDelegate.handle([command.url(config: store.config)])
    }
}
