import SwiftUI
import BatteryGuardShared

/// Wann der Akku voraussichtlich 80 % oder die Zyklusreferenz erreicht – und ob die
/// AppleCare-Frist dafür noch reicht.
struct ReplacementForecastView: View {
    let statusStore: StatusStore
    let history: HistoryStore
    @AppStorage(ReplacementForecastView.appleCareKey) private var appleCareEnd: Double = 0
    static let appleCareKey = "bg.appleCareEnd"

    static func appleCareEndDate(_ defaults: UserDefaults = .standard) -> Date? {
        let value = defaults.double(forKey: appleCareKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private var forecast: BGReplacementForecast {
        BGReplacementForecast.evaluate(
            days: history.capacityDays, currentCycles: statusStore.status.cycleCount,
            cycleLimit: BGBatteryCycleReference.maximumCycles(model: statusStore.systemDiagnostics?.modelIdentifier) ?? 1000,
            appleCareEnd: appleCareEnd > 0 ? Date(timeIntervalSince1970: appleCareEnd) : nil,
            limitChange: LimitChangeStore.current())
    }

    var body: some View {
        let forecast = forecast
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Austauschprognose").font(.headline)
                switch forecast.status {
                case .insufficientData(let collected, let span):
                    Text(history.longTermCapacityEnabled
                         ? L("Noch zu wenig Verlauf: %lld Tageswerte über %lld Tage. Nötig sind mindestens 10 Tageswerte über 30 Tage.", collected, span)
                         : L("Aktiviere oben die Aufzeichnung der Tageswerte. Nach etwa einem Monat erscheint hier eine Prognose."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case .noMeasurableDecline:
                    Text("Bisher keine messbare Abnahme der Kapazitätsquote.").font(.callout)
                case .declining:
                    if let perYear = forecast.changePerYear {
                        Text(L("Abnahme etwa %.1f Prozentpunkte pro Jahr", -perYear)).font(.callout).monospacedDigit()
                    }
                    if let date = forecast.capacityThresholdDate {
                        Text(L("80 %% voraussichtlich um %@", Self.monthText(date))).font(.title3.weight(.light))
                        Text(L("Spanne: %@ bis %@", forecast.capacityThresholdEarliest.map(Self.monthText) ?? "—",
                               forecast.capacityThresholdLatest.map(Self.monthText) ?? L("nicht absehbar")))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("80 % sind in den nächsten 15 Jahren nicht absehbar.").font(.callout)
                    }
                }
                if let rate = forecast.cyclesPerDay {
                    Text(L("%.2f Zyklen pro Tag", rate)).font(.callout).monospacedDigit()
                    if let date = forecast.cycleLimitDate, let limit = forecast.cycleLimit {
                        Text(L("%lld Zyklen voraussichtlich um %@", limit, Self.monthText(date)))
                            .font(.callout)
                    }
                }
                if forecast.settling {
                    Label("Das Ladelimit wurde kürzlich deutlich geändert. Die Prognose ist einige Wochen lang verzerrt (Anodenüberhang).",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Toggle("AppleCare+ oder Garantie eingetragen", isOn: Binding(
                    get: { appleCareEnd > 0 },
                    set: { appleCareEnd = $0 ? Date().addingTimeInterval(365 * 86400).timeIntervalSince1970 : 0 }))
                if appleCareEnd > 0 {
                    DatePicker("Gültig bis", selection: Binding(
                        get: { Date(timeIntervalSince1970: appleCareEnd) },
                        set: { appleCareEnd = $0.timeIntervalSince1970 }), displayedComponents: .date)
                    if forecast.appleCareReminderDue {
                        Label("Der Schutz endet bald, und der Akku liegt nahe an 80 %. AppleCare+ deckt einen Akkutausch unter 80 % der ursprünglichen Kapazität ab – lass ihn vor Ablauf prüfen.",
                              systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Link("Apple: Deckungsstatus prüfen", destination: URL(string: "https://checkcoverage.apple.com")!)
                        .font(.caption)
                }
                Text("Grundlage ist die Kapazitätsquote aus Maximal- und Designkapazität, nicht Apples „Maximale Kapazität“. Alterung verläuft nicht linear; die Spanne zeigt die Unsicherheit der Schätzung.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func monthText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
