import SwiftUI
import BatteryGuardShared

extension BGMode {
    var localizedName: String {
        switch self {
        case .auto: return L("Auto")
        case .native: return L("Nativ (macOS)")
        case .direct: return L("Direkt (Root)")
        case .systemLimit: return L("macOS-Limit")
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .native: return "apple.logo"
        case .direct: return "cpu"
        case .systemLimit: return "gauge.with.dots.needle.67percent"
        }
    }
    
    var description: String {
        switch self {
        case .auto: return "Automatisch (Empfohlen): Nutzt die SMC-Ladesperre, wenn vorhanden. Sonst hält macOS das Ladelimit."
        case .native: return "Nativ: Beobachtet nur. Das Ladelimit stellst du selbst in den macOS-Batterieeinstellungen ein."
        case .direct: return "Direktmodus nicht implementiert. Bitte Auto oder Nativ wählen."
        case .systemLimit: return "macOS-Limit: B-Guard setzt Apples natives Ladelimit auf die nächste angebotene Stufe (80–100 %). Für Macs ohne SMC-Ladesperre; das Limit gilt auch im Schlaf."
        }
    }
    var localizedDescription: String { L(description) }
}

struct ModePickerView: View {
    @Binding var mode: BGMode
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Modus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Legt fest, wie B-Guard das Ladelimit erzwingt.")
                
                Spacer()
                
                Text(mode.localizedName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 2)
            
            // Glas-Picker Segmentleiste
            HStack(spacing: 3) {
                // Show standard modes, excluding direct unless already selected
                ForEach([BGMode.auto, .native] + (mode == .systemLimit ? [.systemLimit] : []) + (mode == .direct ? [.direct] : []), id: \.self) { m in
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
                    .help(m.localizedDescription)
                }
            }
            .padding(3)
            .adaptiveGlassCard(cornerRadius: 12)
            
            // Dynamische Erklärung des aktuell gewählten Modus
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                
                Text(mode.localizedDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }
}
