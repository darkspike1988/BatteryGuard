import SwiftUI
import BatteryGuardShared

extension BGMode {
    var localizedName: String {
        switch self {
        case .auto: return "Auto"
        case .native: return "Nativ (macOS)"
        case .pendulum: return "Pendel"
        case .direct: return "Direkt (Root)"
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .native: return "apple.logo"
        case .pendulum: return "arrow.left.and.right"
        case .direct: return "cpu"
        }
    }
    
    var description: String {
        switch self {
        case .auto: return "Automatisch: App entscheidet (Standard)"
        case .native: return "Nativ: Überlässt macOS die Ladesteuerung"
        case .pendulum: return "Pendel: Erzwingt Limit durch virtuelles Trennen des Netzteils"
        case .direct: return "Direkt: Nutzt SMC-Hardwaresperre (nur ältere Macs)"
        }
    }
}

struct ModePickerView: View {
    @Binding var mode: BGMode
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Modus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Legt fest, wie BatteryGuard das Ladelimit erzwingt.")
                
                Spacer()
                
                Text(mode.localizedName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 2)
            
            // Glas-Picker Segmentleiste
            HStack(spacing: 3) {
                // Show standard modes, excluding direct unless already selected
                ForEach([BGMode.auto, .native, .pendulum] + (mode == .direct ? [.direct] : []), id: \.self) { m in
                    let isSelected = (m == mode)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            mode = m
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: m.icon)
                                .font(.system(size: 9.5, weight: isSelected ? .bold : .regular))
                            Text(m.localizedName)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 4)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.18))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.40),
                                                            Color.white.opacity(0.10)
                                                        ],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    ),
                                                    lineWidth: 0.5
                                                )
                                        )
                                        .shadow(color: Color.accentColor.opacity(0.20), radius: 3, x: 0, y: 1)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                }
                            }
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .help(m.description)
                }
            }
            .padding(3)
            .adaptiveGlassCard(cornerRadius: 12)
        }
    }
}
