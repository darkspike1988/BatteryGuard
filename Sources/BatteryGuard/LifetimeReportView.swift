import SwiftUI
import BatteryGuardShared

/// Druckbare Seite für den PDF-Bericht; immer hell, unabhängig von der App-Darstellung.
struct LifetimeReportView: View {
    let analysis: BGLifetimeAnalysis
    let createdAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("B-Guard · Akkubericht").font(.title.weight(.semibold))
            Text(L("Erstellt am %@", createdAt.formatted(date: .long, time: .shortened))).foregroundStyle(.secondary)
            Divider()
            LifetimeFactsGrid(analysis: analysis)
            Divider()
            Text("Werte stammen aus lokalen Messungen dieses Macs. Fehlende Zeiträume bleiben Lücken. Der Bericht ist keine Hardwarediagnose und enthält keine Seriennummern.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(40)
        .environment(\.colorScheme, .light)
        .background(.white)
    }
}
