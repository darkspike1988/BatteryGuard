import SwiftUI
import BatteryGuardShared

/// Beantwortet die Frage „Was gilt gerade wirklich?“ mit den Werten, die der Dienst tatsächlich anwendet.
struct EffectivenessView: View {
    let statusStore: StatusStore
    let config: BGConfig

    private var effectiveness: BGEffectiveness {
        BGEffectiveness.evaluate(config: config, status: statusStore.status,
                                 daemonActive: statusStore.isDaemonActive,
                                 daemonCurrent: !statusStore.daemonNeedsUpdate)
    }

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Was gilt gerade wirklich?").font(.headline)
                    Spacer()
                    stateBadge
                }
                Text(stateExplanation)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                    row("Dein Ziel", value: limitText(effectiveness.targetUpperLimit))
                    row("Angewendetes Ziel", value: limitText(effectiveness.appliedUpperLimit))
                    row("macOS-Limit", value: limitText(effectiveness.nativeChargeLimit))
                    row("Steuerungsweg", value: controlPathText)
                    if let external = effectiveness.externalDisplayConnected {
                        row("Externer Monitor", value: external ? L("verbunden") : L("nicht verbunden"))
                    }
                    if let lid = effectiveness.lidClosed {
                        row("Deckel", value: lid ? L("geschlossen") : L("offen"))
                    }
                }
                if effectiveness.state == .limitedByNative || effectiveness.nativeAdvice?.needsAdjustment == true {
                    Button("Batterieeinstellungen öffnen") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
                    }.font(.caption)
                }
            }
        }
    }

    private var stateBadge: some View {
        Label(stateTitle, systemImage: stateSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(stateColor)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(stateColor.opacity(0.12), in: Capsule())
    }

    private var stateTitle: String {
        switch effectiveness.state {
        case .effective: L("wirksam")
        case .limitedByNative: L("begrenzt")
        case .desktopFallback: L("Monitor-/Deckelschutz")
        case .handledByMacOS: L("macOS-Limit")
        case .inactive: L("nicht aktiv")
        case .unsupported: L("nicht unterstützt")
        case .daemonInactive: L("Dienst aus")
        case .daemonOutdated: L("Dienst veraltet")
        }
    }

    private var stateSymbol: String {
        switch effectiveness.state {
        case .effective: "checkmark.seal"
        case .limitedByNative, .desktopFallback: "exclamationmark.triangle"
        case .handledByMacOS: effectiveness.nativeAdvice?.needsAdjustment == true ? "exclamationmark.triangle" : "apple.logo"
        case .inactive: "pause.circle"
        case .unsupported: "questionmark.circle"
        case .daemonInactive: "bolt.slash"
        case .daemonOutdated: "arrow.down.circle"
        }
    }

    private var stateColor: Color {
        switch effectiveness.state {
        case .effective: .green
        case .limitedByNative: .orange
        case .desktopFallback: .secondary
        case .handledByMacOS: effectiveness.nativeAdvice?.needsAdjustment == true ? .orange : .green
        case .inactive: .secondary
        case .unsupported: .orange
        case .daemonInactive, .daemonOutdated: .orange
        }
    }

    private var stateExplanation: String {
        switch effectiveness.state {
        case .effective:
            if effectiveness.controlPath == .macOS {
                return L("macOS hält dein Ladelimit. B-Guard beobachtet den Zustand und greift nicht ein.")
            }
            if effectiveness.controlPath == .nativeLimit {
                return L("B-Guard setzt dein Ziel über das macOS-Ladelimit durch. macOS hält es auch im Schlaf.")
            }
            return L("B-Guard setzt dein Ziel über den erkannten Steuerungsweg durch. Messwerte und Verlauf bleiben lokal.")
        case .limitedByNative:
            return L("macOS begrenzt früher als dein B-Guard-Ziel. Hebe das native Limit in den Batterieeinstellungen an, wenn du höher laden willst. B-Guard ändert diese Systemeinstellung nicht.")
        case .desktopFallback:
            return L("Bei externem Monitor oder geschlossenem Deckel bleibt das Netzteil verbunden. Ohne separate Ladesperre übernimmt macOS das Laden; das B-Guard-Ziel wird nicht erzwungen.")
        case .handledByMacOS:
            return nativeAdviceText
        case .inactive:
            return config.enabled ? L("Der Schutz ist gerade pausiert. Nach Ablauf gilt wieder dein gespeichertes Profil.") : L("Der Ladeschutz ist ausgeschaltet. macOS lädt nach seinen eigenen Einstellungen.")
        case .unsupported:
            return L("Auf diesem Modell wurde kein passender Steuerungsweg für das Ladelimit erkannt. B-Guard zeigt nur Messwerte an.")
        case .daemonInactive:
            return L("Der Hintergrunddienst liefert keine aktuellen Werte. Starte ihn in den Einstellungen oder prüfe den Dienststatus.")
        case .daemonOutdated:
            return L("Der Hintergrunddienst ist älter als diese App. Aktualisiere ihn in den Einstellungen, damit die angezeigten Werte belastbar sind.")
        }
    }

    /// macOS Tahoe 26.4+ hält auf Apple silicon ein Ladelimit von 80 bis 100 % (Apple 102338).
    private var nativeAdviceText: String {
        guard let advice = effectiveness.nativeAdvice, let target = effectiveness.targetUpperLimit else {
            return L("Ohne separate Ladesperre hält macOS das Ladelimit. B-Guard beobachtet und greift nicht ein.")
        }
        if effectiveness.nativeChargeLimit == nil {
            return L("Kein macOS-Ladelimit erkannt. Ab macOS 26.4 lässt es sich unter Systemeinstellungen → Batterie einstellen; auf älteren Versionen hilft „Optimiertes Laden“.")
        }
        if advice.targetBelowNativeMinimum {
            return L("Dein Ziel von %lld %% liegt unter dem macOS-Minimum von 80 %%. Ohne separate Ladesperre hält dieser Mac höchstens bei 80 %%; stelle das macOS-Ladelimit auf 80 %%.", target)
        }
        if advice.needsAdjustment {
            return L("Ohne separate Ladesperre hält macOS das Ladelimit. Stelle es in den Batterieeinstellungen auf %lld %%, passend zu deinem Ziel.", advice.recommendedLimit)
        }
        return L("Das macOS-Ladelimit passt zu deinem Ziel. B-Guard beobachtet und greift nicht ein.")
    }

    private var controlPathText: String {
        switch effectiveness.controlPath {
        case .none: L("nicht erkannt")
        case .chargeLock: L("SMC-Ladesperre")
        case .adapterSwitch: L("Netzteil-Schalter")
        case .macOS: L("macOS-Ladelimit")
        case .nativeLimit: L("macOS-Ladelimit, von B-Guard gesetzt")
        }
    }

    private func limitText(_ value: Int?) -> String {
        value.map { L("%lld %%", $0) } ?? "—"
    }

    private func row(_ title: String, value: String) -> some View {
        GridRow {
            Text(L(title)).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.callout).monospacedDigit()
        }
    }
}
