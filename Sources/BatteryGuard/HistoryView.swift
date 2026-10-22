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

/// `body` liest die Messpunkte vielfach (Diagramm, Zusammenfassung, Auswahl, Tasten).
/// Der Cache berechnet sie nur neu, wenn sich Verlauf, Messwert, Zeitraum oder Minute ändern.
private final class HistoryPointCache {
    struct Key: Equatable {
        let count: Int
        let first: Date?
        let last: Date?
        let metric: HistoryMetric
        let hours: Int
        let minute: Int
    }
    var key: Key?
    var filtered: [BGHistorySample] = []
    var points: [HistoryPoint] = []
    var chartPoints: [HistoryPoint] = []

    /// Swift Charts zeichnet jede Marke einzeln; 10.080 Punkte für sieben Tage sind unnötig.
    /// Abschnittsgrenzen bleiben erhalten, damit Lücken sichtbar bleiben.
    static func thinned(_ points: [HistoryPoint], limit: Int = 720) -> [HistoryPoint] {
        guard points.count > limit else { return points }
        let step = Int((Double(points.count) / Double(limit)).rounded(.up))
        var result: [HistoryPoint] = []
        result.reserveCapacity(limit + 32)
        for (index, point) in points.enumerated() {
            let edge = index == 0 || index == points.count - 1
                || points[index - 1].segment != point.segment || points[index + 1].segment != point.segment
            if edge || index % step == 0 { result.append(point) }
        }
        return result
    }
}

private enum LongTermMetric: String, CaseIterable, Identifiable {
    case capacity = "Kapazitätsquote", cycles = "Zyklen", temperature = "Temperatur"
    var id: String { rawValue }
    var unit: String { switch self { case .capacity: "%"; case .cycles: L("Zyklen"); case .temperature: "°C" } }
    func value(_ day: BGCapacityDay) -> Double? {
        switch self {
        case .capacity: day.mean
        case .cycles: day.cycleMean
        case .temperature: day.temperatureMaximum
        }
    }
}

private struct LongTermPoint: Identifiable {
    var id: Date { day }
    let day: Date
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
    @State private var longTermMetric: LongTermMetric = .capacity
    @State private var longTermDays = 365

    @State private var cache = HistoryPointCache()

    private func refreshCache() {
        let now = Date()
        let samples = history.samples
        let key = HistoryPointCache.Key(count: samples.count, first: samples.first?.timestamp,
                                        last: samples.last?.timestamp, metric: metric, hours: hours,
                                        minute: Int(now.timeIntervalSince1970 / 60))
        guard cache.key != key else { return }
        cache.key = key
        let cutoff = now.addingTimeInterval(-Double(hours) * 3600)
        let filtered = samples.filter { $0.timestamp >= cutoff }
        var segment = 0
        var previous: Date?
        let points = filtered.compactMap { sample -> HistoryPoint? in
            guard let value = metric.value(sample), value.isFinite else { previous = nil; segment += 1; return nil }
            if let previous, sample.timestamp.timeIntervalSince(previous) > 120 { segment += 1 }
            previous = sample.timestamp
            return HistoryPoint(time: sample.timestamp, value: value, segment: segment)
        }
        cache.filtered = filtered
        cache.points = points
        cache.chartPoints = HistoryPointCache.thinned(points)
    }

    private var filtered: [BGHistorySample] { refreshCache(); return cache.filtered }
    private var points: [HistoryPoint] { refreshCache(); return cache.points }
    private var chartPoints: [HistoryPoint] { refreshCache(); return cache.chartPoints }

    /// Binäre Suche: Hover-Ereignisse kommen sehr häufig.
    private var selectedPoint: HistoryPoint? {
        guard let selectedTime else { return nil }
        let points = self.points
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].time < selectedTime { low = mid + 1 } else { high = mid }
        }
        if low > 0, abs(points[low - 1].time.timeIntervalSince(selectedTime)) <= abs(points[low].time.timeIntervalSince(selectedTime)) {
            return points[low - 1]
        }
        return points[low]
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
                                ForEach(HistoryMetric.allCases) { Text(L($0.rawValue)).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
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
                                Text(points.last.map { String(format: "%.1f W", $0.value) } ?? L("Nicht verfügbar"))
                                    .monospacedDigit()
                            }.font(.callout)
                            Text("Plus: Akku lädt. Minus: Akku entlädt. 0 W: kein Stromfluss am Akku. Dies ist nicht der Gesamtverbrauch des Macs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if points.isEmpty && metric != .charge && !filtered.isEmpty {
                            ContentUnavailableView("Messwert nicht verfügbar", systemImage: "waveform.path",
                                description: Text(L("Für diesen Zeitraum liefert der Dienst keine Messwerte für %@.", L(metric.rawValue).lowercased())))
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
                                .accessibilityLabel(L("Zusammenfassung: %@", chartSummary))
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
                longTermPanel
                summaryPanel
                weeklyPanel
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
            return L("Keine Messwerte verfügbar.")
        }
        let from = first.time.formatted(date: .abbreviated, time: .shortened)
        let until = last.time.formatted(date: .abbreviated, time: .shortened)
        let range = L("Minimum %.1f %@ · Maximum %.1f %@", minimum, metric.unit, maximum, metric.unit)
        return L("%d Messpunkte von %@ bis %@. %@.", samples.count, from, until, range)
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
        let chartPoints = self.chartPoints
        let segmentCounts = Dictionary(grouping: chartPoints, by: \.segment).mapValues { $0.count }
        return Chart {
            ForEach(chartPoints) { point in
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
        .accessibilityLabel(L("%@ der letzten %lld Stunden", L(metric.rawValue), hours))
    }

    private var valueDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let lower = min(values.min() ?? 0, metric == .power ? 0 : 20)
        let upper = max(values.max() ?? 1, lower + 1)
        let margin = max((upper - lower) * 0.15, 2)
        return (lower - margin)...(upper + margin)
    }

    private var longTermPoints: [LongTermPoint] {
        let cutoff = Date().addingTimeInterval(-Double(longTermDays) * 86400)
        var segment = 0
        var previous: Date?
        return history.capacityDays
            .filter { $0.isValid && $0.day >= cutoff }
            .sorted { $0.day < $1.day }
            .compactMap { day in
                guard let value = longTermMetric.value(day), value.isFinite else { return nil }
                if let previous, day.day.timeIntervalSince(previous) > 1.5 * 86400 { segment += 1 }
                previous = day.day
                return LongTermPoint(day: day.day, value: value, segment: segment)
            }
    }

    private var longTermPanel: some View {
        let points = longTermPoints
        return BGPanel {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Akkugesundheit über 12 Monate").font(.headline)
                        Text("Tageswerte aus den verfügbaren Messungen. Lücken bleiben sichtbar und werden nicht interpoliert.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { exportCapacityCSV() } label: { Label("CSV exportieren", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).disabled(history.capacityDays.isEmpty)
                }
                Toggle("Tägliche Tageswerte lokal aufzeichnen", isOn: Binding(
                    get: { history.longTermCapacityEnabled },
                    set: { history.longTermCapacityEnabled = $0 }))
                    .font(.callout)
                if let error = history.capacityError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                if !history.longTermCapacityEnabled {
                    ContentUnavailableView("Langzeitverlauf ist aus",
                        systemImage: "calendar.badge.clock",
                        description: Text("Aktiviere die Aufzeichnung, damit B-Guard höchstens ein Jahr lang einen Tageswert für Kapazitätsquote, Zyklen und Temperatur speichert. Die Datei bleibt auf diesem Mac."))
                        .frame(height: 180)
                } else if points.count < 2 {
                    ContentUnavailableView("Noch keine zwei Tageswerte",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Sobald an zwei Tagen aktuelle Messwerte vorliegen, erscheint hier die erste Linie. Der Verlauf wächst nur, während die App läuft."))
                        .frame(height: 180)
                } else {
                    HStack {
                        Picker("Messwert", selection: $longTermMetric) {
                            ForEach(LongTermMetric.allCases) { Text(L($0.rawValue)).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 330)
                        Spacer()
                        Picker("Zeitraum", selection: $longTermDays) {
                            Text("30 Tage").tag(30)
                            Text("90 Tage").tag(90)
                            Text("12 Monate").tag(365)
                        }.labelsHidden().frame(width: 130)
                    }
                    longTermChart(points)
                    longTermSummary(points)
                }
            }
        }
    }

    private func longTermChart(_ points: [LongTermPoint]) -> some View {
        let chartPoints = self.chartPoints
        let segmentCounts = Dictionary(grouping: chartPoints, by: \.segment).mapValues { $0.count }
        return Chart {
            ForEach(chartPoints) { point in
                LineMark(x: .value("Tag", point.day), y: .value(longTermMetric.unit, point.value),
                         series: .value("Abschnitt", point.segment))
                    .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2))
                if segmentCounts[point.segment] == 1 {
                    PointMark(x: .value("Tag", point.day), y: .value(longTermMetric.unit, point.value))
                        .foregroundStyle(Color.accentColor).symbolSize(18)
                }
            }
        }
        .chartYScale(domain: longTermDomain(points))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
        .frame(height: 240)
        .accessibilityLabel(L("%@ über %lld Tage", L(longTermMetric.rawValue), longTermDays))
    }

    private func longTermSummary(_ points: [LongTermPoint]) -> some View {
        let values = points.map(\.value)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        var parts = [L("%d Tageswerte", points.count),
                     L("Minimum %.1f %@ · Maximum %.1f %@", minimum, longTermMetric.unit, maximum, longTermMetric.unit)]
        if longTermMetric == .capacity {
            let cutoff = Date().addingTimeInterval(-Double(longTermDays) * 86400)
            let days = history.capacityDays.filter { $0.isValid && $0.day >= cutoff }
            if let delta = BGCapacityTrend.change(days) {
                parts.append(L("Veränderung %.1f Prozentpunkte", delta))
            } else {
                parts.append(L("Kein belastbarer Vergleich: Quellen, Designkapazität oder Systemversion wechselten."))
            }
        }
        return Text(parts.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func longTermDomain(_ points: [LongTermPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        switch longTermMetric {
        case .capacity:
            return max(0, minimum - 5)...min(110, max(maximum + 5, minimum + 1))
        case .cycles:
            let margin = max((maximum - minimum) * 0.15, 5)
            return max(0, minimum - margin)...(maximum + margin)
        case .temperature:
            let margin = max((maximum - minimum) * 0.15, 2)
            return (minimum - margin)...(maximum + margin)
        }
    }

    private func exportCapacityCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "B-Guard-Akkuverlauf-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BGCapacityTrend.csv(history.capacityDays).write(to: url, atomically: true, encoding: .utf8)
            exportFailed = false
            exportMessage = L("Tageswerte als %@ gespeichert.", url.lastPathComponent)
        } catch {
            exportFailed = true
            exportMessage = L("Export fehlgeschlagen: %@", error.localizedDescription)
        }
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

    private var weeklyPanel: some View {
        let report = BGHistory.weeklyReport(history.samples, now: Date())
        return BGPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Wochenbericht").font(.headline)
                    Spacer()
                    Text(L("%@ bis %@", report.from.formatted(date: .abbreviated, time: .omitted),
                           report.to.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 24) {
                    statistic("Aufgezeichnet", value: duration(report.summary.observedSeconds))
                    statistic("Ab 90 % Ladung", value: duration(report.summary.highChargeSeconds))
                    statistic("Ab 40 °C", value: duration(report.summary.hotSeconds))
                }
                HStack(spacing: 24) {
                    Text(L("Volllade-Tage: %lld", report.fullChargeDays)).font(.callout)
                    Text(L("Höchster Zyklusstand: %@", report.highestCycleCount.map(String.init) ?? "—"))
                        .font(.callout)
                }.foregroundStyle(.secondary)
                Text("Der Bericht rechnet nur mit lückenlos aufgezeichneten Minuten. Er bewertet deine Nutzung nicht und ersetzt keine Diagnose.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.system(size: 26, weight: .light)).monospacedDigit()
            Text(L(label)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return L("0 min") }
        if seconds < 3600 { return L("%lld min", Int(seconds / 60)) }
        return L("%.1f h", seconds / 3600)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "B-Guard-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BGHistory.csv(history.samples).write(to: url, atomically: true, encoding: .utf8)
            exportFailed = false
            exportMessage = L("Verlauf als %@ gespeichert.", url.lastPathComponent)
        } catch {
            exportFailed = true
            exportMessage = L("Export fehlgeschlagen: %@", error.localizedDescription)
        }
    }
}
