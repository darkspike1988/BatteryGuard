import Foundation
import Observation
import BatteryGuardShared

/// Verlauf als JSON Lines: Jede Messung hängt eine Zeile an. Die Datei wird nur bei
/// Bedarf verdichtet (etwa einmal täglich), statt jede Minute komplett neu zu entstehen.
actor HistoryRepository {
    let url: URL
    /// Frühere Versionen speicherten ein JSON-Array; es wird einmalig übernommen.
    let legacyURL: URL?
    private var samples: [BGHistorySample]?
    private var linesInFile = 0
    private(set) var recoveryNotice: String?
    /// Höchstens einen Tag veralteter Zeilen in der Datei behalten, dann verdichten.
    static let compactionSlack = 1440
    /// Liefert den Schlüssel für das Lesen verschlüsselter und das Schreiben neuer Dateien (nil = Klartext).
    private let readCipher: @Sendable () -> BGHistoryCipher?
    private let writeCipher: @Sendable () -> BGHistoryCipher?
    /// Eine verschlüsselte Datei wird immer als Ganzes neu geschrieben, nie angehängt.
    private var fileEncrypted = false

    init(url: URL, legacyURL: URL? = nil,
         readCipher: @escaping @Sendable () -> BGHistoryCipher? = { nil },
         writeCipher: @escaping @Sendable () -> BGHistoryCipher? = { nil }) {
        self.url = url
        self.legacyURL = legacyURL
        self.readCipher = readCipher
        self.writeCipher = writeCipher
    }

    func load(now: Date = Date()) throws -> [BGHistorySample] {
        if let samples { return samples }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path), let legacyURL, fileManager.fileExists(atPath: legacyURL.path) {
            return try migrate(from: legacyURL, now: now)
        }
        guard fileManager.fileExists(atPath: url.path) else {
            samples = []
            return []
        }
        // Lesefehler (z. B. fehlende Rechte) dürfen keine vermeintliche Reparatur auslösen.
        let raw = try Data(contentsOf: url)
        fileEncrypted = BGHistoryCipher.isEncrypted(raw)
        let data = try decrypted(raw)
        // Verschlüsselte Dateien früherer Versionen enthalten ein JSON-Array statt JSON Lines.
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == UInt8(ascii: "[") {
            return try adoptArray(data, from: nil, now: now)
        }
        let decoded = BGHistory.decodeLines(data)
        if decoded.samples.isEmpty && decoded.invalidLines > 0 {
            try quarantine(url)
            samples = []
            return []
        }
        let recent = BGHistory.recentSamples(decoded.samples, now: now)
        samples = recent
        linesInFile = decoded.lineCount
        // Beschädigte oder abgeschnittene Zeilen nicht weiter mitschleppen.
        if decoded.invalidLines > 0 || !decoded.endsCleanly { try rewrite(recent) }
        return recent
    }

    /// Ohne Schlüssel nicht als Beschädigung behandeln: Die Datei bleibt unangetastet.
    private func decrypted(_ data: Data) throws -> Data {
        guard BGHistoryCipher.isEncrypted(data) else { return data }
        guard let cipher = readCipher() else { throw CocoaError(.fileReadNoPermission) }
        return try cipher.open(data)
    }

    private func migrate(from legacy: URL, now: Date) throws -> [BGHistorySample] {
        try adoptArray(decrypted(Data(contentsOf: legacy)), from: legacy, now: now)
    }

    private func adoptArray(_ data: Data, from legacy: URL?, now: Date) throws -> [BGHistorySample] {
        let loaded: [BGHistorySample]
        do {
            loaded = try BGJSON.decoder().decode([BGHistorySample].self, from: data)
        } catch is DecodingError {
            try quarantine(legacy ?? url)
            samples = []
            return []
        }
        let recent = BGHistory.recentSamples(loaded, now: now)
        try rewrite(recent)
        if let legacy { try? FileManager.default.removeItem(at: legacy) }
        samples = recent
        return recent
    }

    private func quarantine(_ file: URL) throws {
        let backup = file.deletingLastPathComponent()
            .appendingPathComponent("history-recovery-\(UUID().uuidString).json")
        // Erst sichern. Scheitert das Verschieben, bleibt die Originaldatei unangetastet.
        try FileManager.default.moveItem(at: file, to: backup)
        recoveryNotice = L("Beschädigter Verlauf wurde in %@ gesichert. Neue Messungen werden wieder aufgezeichnet.", backup.lastPathComponent)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    private func rewrite(_ samples: [BGHistorySample]) throws {
        try prepareDirectory()
        let plain = try BGHistory.encodeLines(samples)
        let cipher = writeCipher()
        try (cipher.map { try $0.seal(plain) } ?? plain).write(to: url, options: .atomic)
        fileEncrypted = cipher != nil
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        linesInFile = samples.count
    }

    private func append(_ sample: BGHistorySample) throws {
        try prepareDirectory()
        let line = try BGHistory.encodeLine(sample)
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: line)
        linesInFile += 1
    }

    func record(_ status: BGStatus, now: Date = Date()) throws -> [BGHistorySample] {
        let previous = try load(now: now)
        let next = BGHistory.recording(status, in: previous, now: now)
        guard next != previous else { return previous }
        let canAppend = !fileEncrypted && writeCipher() == nil
        if canAppend, let sample = next.last, BGHistory.isAppend(next, to: previous),
           linesInFile < next.count + Self.compactionSlack,
           FileManager.default.fileExists(atPath: url.path) {
            try append(sample)
        } else {
            try rewrite(next)
        }
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
        longTermCapacityEnabled = preview ? !emptyPreview : UserDefaults.standard.bool(forKey: "BGuard.longTermCapacityEnabled")
        repository = HistoryRepository(url: base.appendingPathComponent("BatteryGuard/history.jsonl"),
            legacyURL: base.appendingPathComponent("BatteryGuard/history.json"),
            readCipher: { HistoryKeyStore.cipher() },
            writeCipher: { HistoryKeyStore.isEnabled ? HistoryKeyStore.cipherCreatingKey() : nil })
        if preview {
            samples = emptyPreview ? [] : Self.previewSamples()
            capacityDays = emptyPreview ? [] : Self.previewCapacityDays()
        } else {
            Task { [weak self, capacityRepository] in
                do { self?.capacityDays = try await capacityRepository.load() }
                catch { self?.capacityError = L("Kapazitätsverlauf konnte nicht geladen werden. Die Datei bleibt unverändert.") }
            }
            Task { [weak self, repository] in
                do {
                    self?.samples = try await repository.load()
                    self?.errorMessage = await repository.recoveryNotice
                }
                catch { self?.errorMessage = L("Verlauf konnte nicht geladen werden: %@", error.localizedDescription) }
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
                    let days = try await capacityRepository.record(status)
                    self?.capacityDays = days
                    self?.capacityError = nil
                    NotificationManager.shared.checkAppleCare(days: days, status: status)
                } catch { self?.capacityError = L("Kapazitätsverlauf konnte nicht gespeichert werden. Bestehende Daten bleiben erhalten.") }
            }
        }
        Task { [weak self, repository] in
            do {
                let updated = try await repository.record(status)
                if self?.samples != updated { self?.samples = updated }
                self?.errorMessage = await repository.recoveryNotice
                NotificationManager.shared.checkWeeklyReport(samples: updated)
            } catch {
                self?.errorMessage = L("Verlauf konnte nicht gespeichert werden: %@", error.localizedDescription)
            }
        }
    }

    private static func previewCapacityDays() -> [BGCapacityDay] {
        let now = Date()
        return (0..<180).map { index in
            let day = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 86400) * 86400
                - Double(179 - index) * 86400)
            let ratio = 96.5 + sin(Double(index) / 21) * 1.2 - Double(index) / 900
            return BGCapacityDay(day: day, maximumSource: .rawMaxCapacity, designSource: .designCapacity,
                                 designCapacity: 5000, osVersion: "27.0",
                                 count: 900, ratioSum: ratio * 900, minimum: ratio - 0.4, maximum: ratio + 0.4,
                                 firstSampledAt: day, lastSampledAt: day.addingTimeInterval(80_000),
                                 cycleSum: Double(120 + index), cycleSamples: 1,
                                 temperatureMaximum: 30 + Double(index % 7))
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
