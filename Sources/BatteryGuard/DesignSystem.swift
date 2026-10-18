import SwiftUI
import BatteryGuardShared

// Ruhige Systemmaterialien, eine Akzentfarbe, klare Hierarchie.
struct BGPanel<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.055)))
    }
}

struct BGSectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L(title)).font(.title2.weight(.semibold))
            Text(L(subtitle)).font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension BGStatus {
    /// Older daemons expose their desktop fallback through this stable decision message.
    var usesNativeDesktopFallback: Bool {
        state == .disabled && message?.hasPrefix("Monitor-/Deckelschutz:") == true
    }

    func displayTitle(active: Bool, config: BGConfig) -> String {
        guard active else { return L("Keine Verbindung zum Dienst") }
        if state == .unsupported { return L("Ladesteuerung nicht verfügbar") }
        if config.isPaused(at: Date()) { return L("Schutz vorübergehend pausiert") }
        if config.mode == .native {
            return L(isChargingHardware ? "macOS lädt den Akku" : (pluggedIn ? "macOS steuert das Laden" : "Akkubetrieb"))
        }
        switch state {
        case .charging: return L(isChargingHardware ? "Akku wird geladen" : "Laden freigegeben")
        case .holding: return L("Laden pausiert")
        case .discharging: return L("Akku entlädt am Netzteil")
        case .onBattery: return L("Akkubetrieb")
        case .disabled: return L(config.enabled ? "macOS übernimmt das Laden" : "Ladeschutz ausgeschaltet")
        case .unsupported: return L("Ladesteuerung nicht verfügbar")
        }
    }

    func displayDetail(active: Bool, config: BGConfig) -> String {
        guard active else { return L("Öffne die Einstellungen, um den Hintergrunddienst zu prüfen.") }
        if config.mode == .native { return nativeChargeLimit.map { L("macOS-Ladelimit: %lld %%. In den Batterieeinstellungen anpassbar.", $0) }
                ?? L("Das Ladelimit wird in den macOS-Batterieeinstellungen festgelegt.") }
        if let message, !message.isEmpty { return StatusMessageLocalizer.localized(message) }
        return L(pluggedIn ? "Mit Netzteil verbunden" : "Vom Akku versorgt")
    }

    func tint(active: Bool) -> Color {
        guard active else { return .secondary }
        if let temperatureCelsius, temperatureCelsius >= 40 { return .orange }
        switch state {
        case .charging: return .green
        case .holding: return .accentColor
        case .discharging: return .orange
        case .unsupported: return .orange
        case .onBattery: return percent <= 20 ? .orange : .primary
        case .disabled: return .secondary
        }
    }
}

struct BatteryHeroView: View {
    let status: BGStatus
    let config: BGConfig
    let active: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 22) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.07), lineWidth: 5)
                    Circle().trim(from: 0, to: active && status.hasBatteryPercent ? Double(status.percent) / 100 : 0)
                        .stroke(status.tint(active: active), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: active ? (status.isChargingHardware ? "bolt.fill" : "shield.lefthalf.filled") : "exclamationmark")
                        .font(.system(size: compact ? 23 : 30, weight: .medium))
                        .foregroundStyle(status.tint(active: active))
                }
                .frame(width: compact ? 64 : 84, height: compact ? 64 : 84)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(active && status.hasBatteryPercent ? String(status.percent) : "—")
                            .font(.system(size: compact ? 48 : 64, weight: .light))
                        Text("%").font(.system(size: compact ? 23 : 28, weight: .light)).foregroundStyle(.secondary)
                    }.monospacedDigit()
                    Text(status.displayTitle(active: active, config: config))
                        .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text(status.displayDetail(active: active, config: config))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProfilePickerView: View {
    @Bindable var store: ConfigStore
    var compact = false
    var body: some View {
        HStack(spacing: 8) {
            ForEach(BGProfile.allCases) { profile in
                let selected = profile.matches(store.config)
                Button { store.apply(profile) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: profile.symbol).font(.system(size: 18, weight: .regular))
                        Text(profile.localizedTitle).font(.caption.weight(.medium))
                        Text("\(profile.upper) %").font(.caption).foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, compact ? 12 : 16)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .background(selected ? Color.accentColor.opacity(0.085) : Color.primary.opacity(0.025),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.3) : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("%@, Ladelimit %lld Prozent", profile.localizedTitle, profile.upper))
                .accessibilityValue(L(selected ? "Ausgewählt" : "Nicht ausgewählt"))
                .help(L("Laden ab %lld %%, stoppen bei %lld %%. Deine weiteren Schutzeinstellungen bleiben erhalten.", profile.lower, profile.upper))
            }
        }
        .disabled(store.config.mode == .native || store.config.mode == .direct)
    }
}
