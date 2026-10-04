import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppKit
import BatteryGuardShared

private enum HistoryMetric: String, CaseIterable, Identifiable {
    case charge = "Ladung", temperature = "Temperatur", power = "Leistung"
    var id: String { rawValue }
    var unit: String { switch self { case .charge: "%"; case .temperature: "°C"; case .power: "W" } }
    func value(_ sample: BGHistorySample) -> Double? {
        switch self { case .charge: Double(sample.percent); case .temperature: sample.temperature; case .power: sample.watts }
    }
}

private struct HistoryPoint: Identifiable {
    var id: Date { time }
    let time: Date
    let value: Double
    let segment: Int
}

struct HistoryView: View {
    let history: HistoryStore
    let currentConfig: BGConfig
    @State private var metric: HistoryMetric = .charge
    @State private var hours = 24
    @State private var selectedTime: Date?
    @State private var exportMessage: String?
    @State private var exportFailed = false

    private var filtered: [BGHistorySample] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return history.samples.filter { $0.timestamp >= cutoff }
    }
    private var points: [HistoryPoint] {
        var segment = 0
        var previous: Date?
        return filtered.compactMap { sample in
            guard let value = metric.value(sample), value.isFinite else { previous = nil; segment += 1; return nil }
            if let previous, sample.timestamp.timeIntervalSince(previous) > 120 { segment += 1 }
            previous = sample.timestamp
            return HistoryPoint(time: sample.timestamp, value: value, segment: segment)
        }
    }
    private var selectedPoint: HistoryPoint? {
        guard let selectedTime else { return nil }
        return points.min { abs($0.time.timeIntervalSince(selectedTime)) < abs($1.time.timeIntervalSince(selectedTime)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    BGSectionHeading(title: "Dein Akku, im Verlauf.", subtitle: "Sieben Tage lokal gespeichert. Jede Minute ein Messpunkt.")
                    Spacer()
                    Button { exportCSV() } label: { Label("CSV exportieren", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).disabled(history.samples.isEmpty)
                }
                if let error = history.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                BGPanel {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Picker("Messwert", selection: $metric) {
                                ForEach(HistoryMetric.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).frame(maxWidth: 280)
                            Spacer()
                            Picker("Zeitraum", selection: $hours) {
                                Text("24 Stunden").tag(24)
                                Text("7 Tage").tag(168)
                            }.labelsHidden().frame(width: 130)
                        }
                        if metric == .power {
                            HStack {
                                Text("Akkuleistung").foregroundStyle(.secondary)
                                Spacer()
                                Text(points.last.map { String(format: "%.1f W", $0.value) } ?? "Nicht verfügbar")
                                    .monospacedDigit()
                            }.font(.callout)
                            Text("Plus: Akku lädt. Minus: Akku entlädt. 0 W: kein Stromfluss am Akku. Dies ist nicht der Gesamtverbrauch des Macs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if points.isEmpty && metric != .charge && !filtered.isEmpty {
                            ContentUnavailableView("Messwert nicht verfügbar", systemImage: "waveform.path",
                                description: Text("Für diesen Zeitraum liefert der Dienst keine \(metric.rawValue.lowercased())-Messwerte."))
                                .frame(height: 260)
                        } else if points.count < 2 {
                            ContentUnavailableView {
                                Label("Der Verlauf beginnt jetzt", systemImage: "chart.xyaxis.line")
                            } description: {
                                Text("Lass B-Guard geöffnet. Nach zwei aktuellen Messpunkten erscheint hier die erste Kurve.")
                            }.frame(height: 260)
                        } else {
                            chart
                            Text(chartSummary).font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Zusammenfassung: " + chartSummary)
                            HStack {
                                Button { selectAdjacentPoint(offset: -1) } label: {
                                    Label("Vorheriger Messpunkt", systemImage: "chevron.left")
                                }
                                .keyboardShortcut(.leftArrow, modifiers: [.option])
                                .disabled(points.isEmpty || selectedPoint?.id == points.first?.id)
                                Spacer()
                                Button { selectAdjacentPoint(offset: 1) } label: {
                                    Label("Nächster Messpunkt", systemImage: "chevron.right")
                                }
                                .keyboardShortcut(.rightArrow, modifiers: [.option])
                                .disabled(points.isEmpty || selectedPoint?.id == points.last?.id)
                            }.buttonStyle(.bordered).font(.caption)
                            if let point = selectedPoint {
                                HStack {
                                    Text(point.time.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f %@", point.value, metric.unit)).monospacedDigit()
                                }.font(.caption)
                            } else {
                                Text("Wähle einen Messpunkt über die Kurve, die Buttons oder ⌥← / ⌥→.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                summaryPanel
                Text("Lücken bedeuten, dass keine Messwerte aufgezeichnet wurden, etwa im Ruhezustand. Sie werden nicht als durchgehende Nutzung gerechnet. Eine Ladelimit-Linie zeigt den aktuell eingestellten B-Guard-Zielwert.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let exportMessage {
                    Label(exportMessage, systemImage: exportFailed ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.callout).foregroundStyle(exportFailed ? Color.orange : Color.secondary)
                }
            }.padding(28).frame(maxWidth: 880)
        }
        .onChange(of: metric) { _, _ in selectedTime = nil }
        .onChange(of: hours) { _, _ in selectedTime = nil }
    }

    private var chartSummary: String {
        let samples = points
        guard let first = samples.first, let last = samples.last,
              let minimum = samples.map(\.value).min(), let maximum = samples.map(\.value).max() else {
            return "Keine Messwerte verfügbar."
        }
        let from = first.time.formatted(date: .abbreviated, time: .shortened)
        let until = last.time.formatted(date: .abbreviated, time: .shortened)
        let range = String(format: "Minimum %.1f %@ · Maximum %.1f %@", minimum, metric.unit, maximum, metric.unit)
        return "\(samples.count) Messpunkte von \(from) bis \(until). \(range)."
    }

    private func selectAdjacentPoint(offset: Int) {
        let samples = points
        guard !samples.isEmpty else { return }
        guard let current = selectedPoint,
              let index = samples.firstIndex(where: { $0.id == current.id }) else {
            selectedTime = offset < 0 ? samples.last?.time : samples.first?.time
            return
        }
        selectedTime = samples[min(max(index + offset, 0), samples.count - 1)].time
    }

    private var chart: some View {
        let segmentCounts = Dictionary(grouping: points, by: \.segment).mapValues { $0.count }
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("Zeit", point.time), y: .value(metric.unit, point.value), series: .value("Abschnitt", point.segment))
                    .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2))
                // Isolated samples otherwise disappear when a gap splits the line series.
                if segmentCounts[point.segment] == 1 {
                    PointMark(x: .value("Zeit", point.time), y: .value(metric.unit, point.value))
                        .foregroundStyle(Color.accentColor).symbolSize(18)
                }
            }
            if metric == .charge, currentConfig.mode != .native {
                RuleMark(y: .value("Aktuelles Ladelimit", currentConfig.upperLimit))
                    .foregroundStyle(Color.secondary.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Limit \(currentConfig.upperLimit) %").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let point = selectedPoint {
                RuleMark(x: .value("Auswahl", point.time)).foregroundStyle(Color.secondary.opacity(0.35))
                PointMark(x: .value("Zeit", point.time), y: .value(metric.unit, point.value))
                    .foregroundStyle(Color.accentColor).symbolSize(35)
            }
        }
        .chartYScale(domain: metric == .charge ? 0...100 : valueDomain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
        .chartXSelection(value: $selectedTime)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let frame = proxy.plotFrame {
                                let x = location.x - geo[frame].origin.x
                                selectedTime = proxy.value(atX: x, as: Date.self)
                            }
                        case .ended: selectedTime = nil
                        }
                    }
            }
        }
        .frame(height: 260)
        .accessibilityLabel("\(metric.rawValue) der letzten \(hours) Stunden")
    }

    private var valueDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let lower = min(values.min() ?? 0, metric == .power ? 0 : 20)
        let upper = max(values.max() ?? 1, lower + 1)
        let margin = max((upper - lower) * 0.15, 2)
        return (lower - margin)...(upper + margin)
    }

    private var summaryPanel: some View {
        let summary = BGHistory.summary(filtered)
        return BGPanel {
            VStack(alignment: .leading, spacing: 17) {
                Text("Was die Messwerte zeigen").font(.headline)
                HStack(alignment: .top, spacing: 24) {
                    statistic("Aufgezeichnet", value: duration(summary.observedSeconds))
                    statistic("Ab 90 % Ladung", value: duration(summary.highChargeSeconds))
                    statistic("Ab 40 °C", value: duration(summary.hotSeconds))
                }
                Divider()
                HStack {
                    Text("Höchste Temperatur").foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.peakTemperature.map { String(format: "%.1f °C", $0) } ?? "—").monospacedDigit()
                }.font(.callout)
            }
        }
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.system(size: 26, weight: .light)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "0 min" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return String(format: "%.1f h", seconds / 3600)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "B-Guard-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BGHistory.csv(history.samples).write(to: url, atomically: true, encoding: .utf8)
            exportFailed = false
            exportMessage = "Verlauf als \(url.lastPathComponent) gespeichert."
        } catch {
            exportFailed = true
            exportMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
