import Foundation
import Observation
import BatteryGuardShared

actor HistoryRepository {
    let url: URL
    private var samples: [BGHistorySample]?
    private(set) var recoveryNotice: String?

    init(url: URL) { self.url = url }

    func load(now: Date = Date()) throws -> [BGHistorySample] {
        if let samples { return samples }
        guard FileManager.default.fileExists(atPath: url.path) else {
            samples = []
            return []
        }
        // Lesefehler (z. B. fehlende Rechte) dürfen keine vermeintliche Reparatur auslösen.
        let data = try Data(contentsOf: url)
        let loaded: [BGHistorySample]
        do {
            loaded = try BGJSON.decoder().decode([BGHistorySample].self, from: data)
        } catch is DecodingError {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("history-recovery-\(UUID().uuidString).json")
            // Erst sichern. Scheitert das Verschieben, bleibt die Originaldatei unangetastet.
            try FileManager.default.moveItem(at: url, to: backup)
            recoveryNotice = "Beschädigter Verlauf wurde in \(backup.lastPathComponent) gesichert. Neue Messungen werden wieder aufgezeichnet."
            samples = []
            return []
        }
        let recent = BGHistory.recentSamples(loaded, now: now)
        samples = recent
        return recent
    }

    func record(_ status: BGStatus, now: Date = Date()) throws -> [BGHistorySample] {
        let previous = try load(now: now)
        let next = BGHistory.recording(status, in: previous, now: now)
        guard next != previous else { return previous }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = BGJSON.encoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        samples = next
        return next
    }
}

@MainActor
@Observable
final class HistoryStore {
    var longTermCapacityEnabled: Bool {
        didSet {
            guard !isPreview else { return }
            UserDefaults.standard.set(longTermCapacityEnabled, forKey: "BGuard.longTermCapacityEnabled")
        }
    }
    private(set) var capacityDays: [BGCapacityDay] = []
    private(set) var capacityError: String?
    private let capacityRepository: CapacityTrendRepository
    private(set) var samples: [BGHistorySample] = []
    private(set) var errorMessage: String?
    private let repository: HistoryRepository
    private let isPreview: Bool

    init(preview: Bool = false, emptyPreview: Bool = false) {
        isPreview = preview
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        capacityRepository = CapacityTrendRepository(url: base.appendingPathComponent("BatteryGuard/capacity-days.json"))
        longTermCapacityEnabled = preview ? false : UserDefaults.standard.bool(forKey: "BGuard.longTermCapacityEnabled")
        repository = HistoryRepository(url: base.appendingPathComponent("BatteryGuard/history.json"))
        if preview {
            samples = emptyPreview ? [] : Self.previewSamples()
        } else {
            Task { [weak self, capacityRepository] in
                do { self?.capacityDays = try await capacityRepository.load() }
                catch { self?.capacityError = "Kapazitätsverlauf konnte nicht geladen werden. Die Datei bleibt unverändert." }
            }
            Task { [weak self, repository] in
                do {
                    self?.samples = try await repository.load()
                    self?.errorMessage = await repository.recoveryNotice
                }
                catch { self?.errorMessage = "Verlauf konnte nicht geladen werden: \(error.localizedDescription)" }
            }
        }
    }

    func record(_ status: BGStatus) {
        guard !isPreview else { return }
        if let last = samples.last, last.timestamp <= Date().addingTimeInterval(5),
           status.updatedAt.timeIntervalSince(last.timestamp) < BGHistory.sampleInterval { return }
        if longTermCapacityEnabled {
            Task { [weak self, capacityRepository] in
                do {
                    self?.capacityDays = try await capacityRepository.record(status)
                    self?.capacityError = nil
                } catch { self?.capacityError = "Kapazitätsverlauf konnte nicht gespeichert werden. Bestehende Daten bleiben erhalten." }
            }
        }
        Task { [weak self, repository] in
            do {
                let updated = try await repository.record(status)
                if self?.samples != updated { self?.samples = updated }
                self?.errorMessage = await repository.recoveryNotice
            } catch {
                self?.errorMessage = "Verlauf konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }
    }

    private static func previewSamples() -> [BGHistorySample] {
        let now = Date()
        return (0..<240).map { index in
            var s = BGStatus()
            s.updatedAt = now.addingTimeInterval(Double(index - 239) * 60)
            s.percent = index < 70 ? 58 + index / 3 : 80
            s.temperatureCelsius = 28 + sin(Double(index) / 24) * 2
            s.watts = index < 70 ? 24 : 0
            s.state = index < 70 ? .charging : .holding
            s.pluggedIn = true
            s.healthPercent = 96
            s.cycleCount = 142
            return BGHistorySample(status: s)
        }
    }
}
