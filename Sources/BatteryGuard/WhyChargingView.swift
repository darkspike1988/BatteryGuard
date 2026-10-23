import SwiftUI
import BatteryGuardShared

/// Beantwortet „Warum lädt mein Mac (nicht)?“ mit dem wichtigsten Grund zuerst.
struct WhyChargingView: View {
    let statusStore: StatusStore
    let config: BGConfig

    private var reasons: [BGChargingReason] {
        BGChargingExplanation.reasons(config: config, status: statusStore.status,
                                      daemonActive: statusStore.isDaemonActive)
    }

    var body: some View {
        let reasons = reasons
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Warum lädt mein Mac so?").font(.headline)
                if let first = reasons.first {
                    reasonRow(first, prominent: true)
                }
                ForEach(Array(reasons.dropFirst().enumerated()), id: \.offset) { _, reason in
                    reasonRow(reason, prominent: false)
                }
                if reasons.contains(where: Self.needsBatterySettings) {
                    Button("Batterieeinstellungen öffnen") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
                    }.font(.caption)
                }
            }
        }
    }

    private static func needsBatterySettings(_ reason: BGChargingReason) -> Bool {
        if case .macOSHoldsLimit = reason { return true }
        return false
    }

    private func reasonRow(_ reason: BGChargingReason, prominent: Bool) -> some View {
        let text = Self.text(for: reason)
        return Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(text.title).font(prominent ? .callout.weight(.semibold) : .callout)
                Text(text.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: Self.symbol(for: reason))
                .foregroundStyle(Self.isWarning(reason) ? Color.orange : Color.secondary)
        }
    }

    private static func isWarning(_ reason: BGChargingReason) -> Bool {
        switch reason {
        case .adapterFlapping, .firmwareBlocksChargeInhibit, .heatProtection, .daemonInactive: true
        default: false
        }
    }

    private static func symbol(for reason: BGChargingReason) -> String {
        switch reason {
        case .daemonInactive: "bolt.slash"
        case .notPluggedIn: "battery.75percent"
        case .macOSObservation, .macOSHoldsLimit: "apple.logo"
        case .protectionOff, .paused: "pause.circle"
        case .heatProtection: "thermometer.high"
        case .fullChargeRequested, .topUp: "battery.100percent.bolt"
        case .travelCharging: "airplane"
        case .adapterFlapping: "cable.connector"
        case .firmwareBlocksChargeInhibit: "lock"
        case .likelyMacOSCalibration: "gauge.with.dots.needle.67percent"
        case .belowLowerLimit, .chargingTowardsLimit: "bolt"
        case .holdingAtLimit: "hand.raised"
        }
    }

    static func text(for reason: BGChargingReason) -> (title: String, detail: String) {
        switch reason {
        case .daemonInactive:
            return (L("Dienst liefert keine Werte"),
                    L("Ohne Hintergrunddienst lässt sich nicht sagen, warum geladen wird. macOS lädt nach seinen eigenen Einstellungen."))
        case .notPluggedIn:
            return (L("Kein Netzteil"), L("Der Mac läuft auf Akku und wird nicht geladen."))
        case .macOSObservation(let limit):
            return (L("macOS-Modus"), limit.map { L("B-Guard beobachtet nur. macOS lädt bis %lld %%.", $0) }
                    ?? L("B-Guard beobachtet nur. macOS lädt nach seinen eigenen Einstellungen."))
        case .protectionOff:
            return (L("Schutz ausgeschaltet"), L("macOS lädt nach seinen eigenen Einstellungen."))
        case .paused(let until):
            return (L("Schutz pausiert"),
                    L("Bis %@ lädt macOS nach seinen eigenen Einstellungen.", until.formatted(date: .omitted, time: .shortened)))
        case .heatProtection:
            return (L("Hitzeschutz"), L("Der Akku ist zu warm. B-Guard lädt erst nach dem Abkühlen weiter."))
        case .fullChargeRequested:
            return (L("Vollladung angefordert"), L("Du hast einmal 100 % angefordert. Danach gilt wieder dein Profil."))
        case .travelCharging(let readyAt):
            return (L("Reiseladung"),
                    L("Der Mac lädt auf 100 %%, damit er um %@ voll ist.", readyAt.formatted(date: .omitted, time: .shortened)))
        case .topUp:
            return (L("Auffüllen auf 100 %"), L("Eine Sonderaktion lädt einmal voll. Danach gilt wieder dein Profil."))
        case .adapterFlapping(let count):
            return (L("Netzteil wechselt häufig"),
                    L("In der letzten Stunde %lld-mal getrennt und verbunden. Prüfe Kabel, Stecker und Dock – ein Wackelkontakt startet jedes Mal einen neuen Ladevorgang.", count))
        case .firmwareBlocksChargeInhibit:
            return (L("Ladesperre von macOS gesperrt"),
                    L("Seit macOS 27 erlaubt die Firmware keine separate Ladesperre mehr. Ziele unter 80 % sind deshalb nicht erreichbar; macOS hält sein eigenes Ladelimit."))
        case .macOSHoldsLimit(let limit, let target):
            guard let limit else {
                return (L("macOS hält das Ladelimit"),
                        L("Kein macOS-Ladelimit erkannt. Stelle es unter Systemeinstellungen → Batterie ein."))
            }
            return (L("macOS hält das Ladelimit"), L("macOS lädt bis %lld %%. Dein Ziel ist %lld %%.", limit, target))
        case .likelyMacOSCalibration(let percent, let limit):
            return (L("Wahrscheinlich Kalibrierung durch macOS"),
                    L("Der Akku steht bei %lld %%, über dem Limit von %lld %%. macOS lädt gelegentlich voll, damit die Ladestandsanzeige genau bleibt.", percent, limit))
        case .belowLowerLimit(let lower, let upper):
            return (L("Lädt bis %lld %%", upper), L("Der Akku liegt unter %lld %%. B-Guard lädt bis %lld %% und hält dann.", lower, upper))
        case .holdingAtLimit(let upper):
            return (L("Hält bei %lld %%", upper), L("Der Mac läuft am Netzteil; der Akku wird nicht weiter geladen."))
        case .chargingTowardsLimit(let upper):
            return (L("Lädt bis %lld %%", upper), L("Der Akku liegt im Zielbereich und wird bis zum Ziel geladen."))
        }
    }
}
