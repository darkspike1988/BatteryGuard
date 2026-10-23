import SwiftUI
import BatteryGuardShared

struct BatteryHeaderCardView: View {
    let status: BGStatus
    let config: BGConfig
    let isDaemonActive: Bool
    let visualState: BGVisualState
    
    init(status: BGStatus, config: BGConfig, isDaemonActive: Bool, visualState: BGVisualState) {
        self.status = status
        self.config = config
        self.isDaemonActive = isDaemonActive
        self.visualState = visualState
    }
    
    private var accentColor: Color {
        visualState.accentColor
    }
    
    private var stateDescription: String {
        if !isDaemonActive {
            return L("Hintergrunddienst nicht aktiv")
        }
        switch status.state {
        case .holding:
            return status.message.map(StatusMessageLocalizer.localized) ?? L("Laden pausiert – Netzteil versorgt")
        case .charging:
            if let w = status.watts, w > 0 {
                return L("Lädt (%.1f W)", w)
            }
            return L("Lädt")
        case .discharging:
            return L("Entlädt am Netzteil")
        case .onBattery:
            return L("Akkubetrieb")
        case .disabled:
            return L(config.mode == .native ? "macOS steuert das Laden" : "Schutz deaktiviert")
        case .unsupported:
            return L("Hardware nicht unterstützt")
        }
    }
    
    private var ringIcon: String {
        if !isDaemonActive {
            return "exclamationmark.triangle.fill"
        }
        switch status.state {
        case .holding:
            return "pause.fill"
        case .charging:
            return "bolt.fill"
        case .discharging:
            return "arrow.down"
        case .onBattery:
            return "battery.75percent"
        case .disabled:
            return "slash.circle"
        case .unsupported:
            return "questionmark.circle"
        }
    }
    
    private var mechanismText: String? {
        guard isDaemonActive else { return nil }
        
        if status.nativeLimitControlled != nil {
            return L("macOS-Ladelimit (B-Guard)")
        }
        if status.hasChargeInhibit {
            return L("Native SMC-Sperre")
        } else if status.hasAdapterSwitch || status.chargeCapability?.chargeInhibitBlockedByFirmware == true {
            return L("macOS-Ladelimit")
        }

        if let msg = status.message, !msg.isEmpty {
            return StatusMessageLocalizer.localized(msg)
        }
        return L("SMC aktiv")
    }
    
    private var mechanismTooltip: String {
        guard isDaemonActive else { return "" }
        let keys = status.smcKeysDetected
        if status.hasChargeInhibit {
            return L("Hardware-Ladesperre aktiv (%@). Die Batterie wird präzise auf dem Zielwert gehalten.", keys.joined(separator: ", "))
        } else if status.hasAdapterSwitch || status.chargeCapability?.chargeInhibitBlockedByFirmware == true {
            return L("Keine separate Ladesperre erkannt (%@). macOS hält das Ladelimit; B-Guard beobachtet und warnt.", keys.joined(separator: ", "))
        }
        return L("Steuert die Ladeelektronik.")
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Großer Ladering / Akku-Ring
            ZStack {
                // Ring-Hintergrund
                Circle()
                    .stroke(Color.primary.opacity(0.09), lineWidth: 6.5)
                    .frame(width: 66, height: 66)
                
                // Ring-Füllung mit Verlaufsglanz
                let fraction = CGFloat(min(max(status.percent, 0), 100)) / 100.0
                Circle()
                    .trim(from: 0.0, to: fraction)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                accentColor.opacity(0.75),
                                accentColor,
                                accentColor
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 66, height: 66)
                    .shadow(color: accentColor.opacity(0.40), radius: 4, x: 0, y: 1)
                
                // Zentrales Symbol
                Image(systemName: ringIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .padding(.leading, 2)
            
            // Text-Spalte
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Prozent in SF Rounded mit monospaced Ziffern
                    Text(isDaemonActive && status.hasBatteryPercent ? "\(status.percent) %" : "– %")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    
                    Spacer()
                }
                
                // Ausführliche Statusbeschreibung
                Text(stateDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .adaptiveGlassCard(cornerRadius: 16)
    }
}
