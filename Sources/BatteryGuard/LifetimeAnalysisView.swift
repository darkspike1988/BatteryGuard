import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BatteryGuardShared

/// Langzeitauswertung mit PDF-Bericht. Enthält keine Seriennummern, Profile oder Prozessnamen.
struct LifetimeAnalysisView: View {
    let history: HistoryStore
    @State private var exportMessage: String?

    private var analysis: BGLifetimeAnalysis {
        BGLifetimeAnalysis.analyze(samples: history.samples, capacityDays: history.capacityDays)
    }

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lebensdauer-Analyse").font(.headline)
                LifetimeFactsGrid(analysis: analysis)
                HStack {
                    Button("PDF-Bericht sichern …") { exportPDF() }
                    if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Temperatur, Ladebereiche und Leistung stammen aus dem Minutenverlauf (bis sieben Tage); Kapazität und Zyklen aus den Tageswerten. Trends erscheinen erst ab 30 Tagen. Keine Lebensdauerprognose.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "B-Guard-Akkubericht-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content: LifetimeReportView(analysis: analysis, createdAt: Date()).frame(width: 595))
        var written = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 595, height: max(size.height, 842)))
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: box.height - size.height)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            written = true
        }
        exportMessage = written ? L("Bericht als %@ gespeichert.", url.lastPathComponent) : L("Bericht konnte nicht erstellt werden.")
    }
}
