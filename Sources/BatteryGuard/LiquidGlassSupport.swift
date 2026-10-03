import SwiftUI
import AppKit
import BatteryGuardShared

// MARK: - Visual State & Themes

enum BGVisualState: Sendable {
    case charging
    case holding
    case dischargingOrHeat
    case idleOrBattery
    
    static func resolve(status: BGStatus, isDaemonActive: Bool, config: BGConfig) -> BGVisualState {
        guard isDaemonActive else { return .idleOrBattery }
        
        let isOverheat: Bool = {
            if config.heatProtectionCelsius > 0, let temp = status.temperatureCelsius {
                return temp >= Double(config.heatProtectionCelsius)
            }
            return false
        }()
        
        if isOverheat || status.state == .discharging {
            return .dischargingOrHeat
        }
        
        if status.state == .holding {
            return .holding
        }
        
        if status.state == .charging || (status.pluggedIn && status.isChargingHardware) {
            return .charging
        }
        
        return .idleOrBattery
    }
    
    var accentColor: Color {
        switch self {
        case .charging:
            return Color.green
        case .holding:
            return Color.blue
        case .dischargingOrHeat:
            return Color.orange
        case .idleOrBattery:
            return Color.secondary
        }
    }
    
    var secondaryColor: Color {
        switch self {
        case .charging:
            return Color(red: 0.10, green: 0.75, blue: 0.70) // mint / teal
        case .holding:
            return Color(red: 0.35, green: 0.40, blue: 0.95) // indigo
        case .dischargingOrHeat:
            return Color(red: 0.95, green: 0.30, blue: 0.30) // coral red
        case .idleOrBattery:
            return Color(white: 0.45)
        }
    }
    
    var glowColor: Color {
        accentColor.opacity(0.35)
    }
}

// MARK: - Glass Effect Container Wrapper

struct GlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat? = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            VStack(spacing: spacing ?? 10) {
                content()
            }
        }
    }
}

// MARK: - Adaptive Glass Modifier

struct AdaptiveGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    shape
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    shape
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
        } else if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g = Glass.regular
                if let tint {
                    g = g.tint(tint)
                }
                if interactive {
                    g = g.interactive(true)
                }
                return g
            }()
            content
                .glassEffect(glass, in: shape)
        } else {
            content
                .background(
                    shape
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        }
    }
}

// MARK: - Button Style Adapters

struct AdaptiveGlassButtonModifier: ViewModifier {
    init() {}
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

struct AdaptiveGlassProminentButtonModifier: ViewModifier {
    init() {}
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - View Extensions

extension View {
    func adaptiveGlassCard(cornerRadius: CGFloat = 14, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive))
    }
    
    func adaptiveGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlassModifier(shape: Capsule(), tint: tint, interactive: interactive))
    }
    
    func adaptiveGlassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlassModifier(shape: Circle(), tint: tint, interactive: interactive))
    }
    
    func adaptiveGlassShape<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
    
    func adaptiveGlassButton() -> some View {
        modifier(AdaptiveGlassButtonModifier())
    }
    
    func adaptiveGlassProminentButton() -> some View {
        modifier(AdaptiveGlassProminentButtonModifier())
    }
}
