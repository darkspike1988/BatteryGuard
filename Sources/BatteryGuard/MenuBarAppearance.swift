import SwiftUI
import BatteryGuardShared

/// Persistenter Symbolstil für die Menüleiste.
public enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    case ring = "ring"
    case battery = "battery"
    case shield = "shield"

    public var id: String { rawValue }

    public static let appStorageKey = "bg.menuBarIconStyle"
    public static let defaultStyle: MenuBarIconStyle = .ring

    public var title: String {
        switch self {
        case .ring:
            return "Ladering"
        case .battery:
            return "Batterie"
        case .shield:
            return "Schild"
        }
    }
}

/// Schlüssel für die Anzeige-Einstellungen in UserDefaults.
public enum MenuBarAppearanceKeys {
    public static let iconStyle = "bg.menuBarIconStyle"
    public static let displayMode = "bg.menuBarDisplay"
    public static let showTemperature = "bg.menuShowTemperature"
    public static let showPower = "bg.menuShowPower"
    public static let showHealth = "bg.menuShowHealth"
    public static let showPowerFlow = "bg.menuShowPowerFlow"
}

/// Reine, statisch getypte Beschreibung des Menüleistensymbols.
public struct MenuBarSymbolDescriptor: Equatable, Sendable {
    public let style: MenuBarIconStyle
    public let baseSystemName: String
    public let overlaySystemName: String?
    public let clampedPercent: Int
    public let isWarning: Bool
    public let accessibilityDescription: String

    public init(
        style: MenuBarIconStyle,
        baseSystemName: String,
        overlaySystemName: String?,
        clampedPercent: Int,
        isWarning: Bool,
        accessibilityDescription: String
    ) {
        self.style = style
        self.baseSystemName = baseSystemName
        self.overlaySystemName = overlaySystemName
        self.clampedPercent = clampedPercent
        self.isWarning = isWarning
        self.accessibilityDescription = accessibilityDescription
    }
}

/// Menüleisten-Darstellungslogik, Symbolauswahl und Reset-Helper.
public enum MenuBarAppearance {
    /// Prozentwert sicher auf 0...100 begrenzen.
    public static func clampPercent(_ percent: Int) -> Int {
        min(max(percent, 0), 100)
    }

    /// Reines Mapping auf SF Symbols für Akku-Ladezustand nach Ladeprozent (clamp).
    public static func batterySymbolName(for percent: Int) -> String {
        let clamped = clampPercent(percent)
        switch clamped {
        case ..<13:
            return "battery.0percent"
        case ..<38:
            return "battery.25percent"
        case ..<63:
            return "battery.50percent"
        case ..<88:
            return "battery.75percent"
        default:
            return "battery.100percent"
        }
    }

    /// Testbare reine Symbolauswahl basierend auf statisch getyptem BGStatus.
    public static func symbolDescriptor(
        style: MenuBarIconStyle,
        status: BGStatus,
        isDaemonActive: Bool
    ) -> MenuBarSymbolDescriptor {
        let clamped = clampPercent(status.percent)
        let warning = !isDaemonActive || status.state == .unsupported
        let base: String
        switch style {
        case .ring: base = "circle"
        case .battery: base = batterySymbolName(for: status.percent)
        case .shield: base = "shield"
        }
        let overlay: String?
        let description: String
        if !isDaemonActive {
            overlay = "exclamationmark"
            description = "Hintergrunddienst nicht erreichbar"
        } else if status.state == .unsupported {
            overlay = "exclamationmark"
            description = "Ladesteuerung nicht unterstützt"
        } else if status.isChargingHardware {
            overlay = "bolt.fill"
            description = "Akku lädt bei \(clamped) %"
        } else if status.state == .discharging || status.state == .onBattery || !status.pluggedIn {
            overlay = "arrow.down"
            description = "Akkubetrieb bei \(clamped) %"
        } else if status.state == .holding {
            overlay = "pause.fill"
            description = "Laden pausiert bei \(clamped) %"
        } else {
            overlay = nil
            description = "Netzteil verbunden, Akku lädt nicht"
        }
        return MenuBarSymbolDescriptor(style: style, baseSystemName: base,
                                       overlaySystemName: overlay, clampedPercent: clamped,
                                       isWarning: warning, accessibilityDescription: description)
    }

    /// Setzt ausschließlich Menüleisten-Darstellungs-Defaults in UserDefaults zurück.
    /// Ändert niemals Ladeprofil, Mitteilungen, API oder Autostart.
    public static func resetDisplayPreferences(userDefaults: UserDefaults = .standard) {
        userDefaults.set(MenuBarIconStyle.ring.rawValue, forKey: MenuBarAppearanceKeys.iconStyle)
        userDefaults.set(MenuBarDisplayMode.percent.rawValue, forKey: MenuBarAppearanceKeys.displayMode)
        userDefaults.set(false, forKey: MenuBarAppearanceKeys.showTemperature)
        userDefaults.set(false, forKey: MenuBarAppearanceKeys.showPower)
        userDefaults.set(false, forKey: MenuBarAppearanceKeys.showHealth)
        userDefaults.set(false, forKey: MenuBarAppearanceKeys.showPowerFlow)
    }
}

/// Monochrom gerendertes Menüleistensymbol für B-Guard.
public struct MenuBarIconView: View {
    public let style: MenuBarIconStyle
    public let status: BGStatus
    public let isDaemonActive: Bool

    public init(style: MenuBarIconStyle, status: BGStatus, isDaemonActive: Bool) {
        self.style = style
        self.status = status
        self.isDaemonActive = isDaemonActive
    }

    public var body: some View {
        let descriptor = MenuBarAppearance.symbolDescriptor(
            style: style,
            status: status,
            isDaemonActive: isDaemonActive
        )

        Group {
            switch style {
            case .ring:
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 2)

                    let fraction = CGFloat(descriptor.clampedPercent) / 100.0
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    if let overlay = descriptor.overlaySystemName {
                        Image(systemName: overlay)
                            .font(.system(size: overlay == "shield.fill" || overlay == "pause.fill" ? 6 : 7, weight: .bold))
                            .foregroundStyle(Color.primary)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.trailing, 1)

            case .battery:
                ZStack(alignment: .center) {
                    Image(systemName: descriptor.baseSystemName)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.primary)

                    if let overlay = descriptor.overlaySystemName {
                        Image(systemName: overlay)
                            .font(.system(size: overlay == "pause.fill" ? 5 : 6, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .padding(1.5)
                            .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                            .offset(x: 5, y: 3)
                    }
                }
                .frame(width: 22, height: 14)

            case .shield:
                ZStack(alignment: .center) {
                    Image(systemName: descriptor.baseSystemName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)

                    if let overlay = descriptor.overlaySystemName {
                        Image(systemName: overlay)
                            .font(.system(size: overlay == "pause.fill" ? 5 : 6, weight: .bold))
                            .offset(x: 0, y: -0.5)
                            .foregroundStyle(Color.primary)
                    }
                }
                .frame(width: 14, height: 14)
            }
        }
        .accessibilityLabel(descriptor.accessibilityDescription)
    }
}
