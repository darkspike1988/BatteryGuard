import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct HistoryRepositoryTests {
    private func fixture() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("history.jsonl"))
    }

    private func status(at date: Date) -> BGStatus {
        var status = BGStatus()
        status.updatedAt = date
        status.percent = 65
        return status
    }

    @Test func corruptHistoryIsPreservedAndRecordingRecovers() async throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("{broken history".utf8)
        try original.write(to: url)
        let repository = HistoryRepository(url: url)
        #expect(try await repository.load().isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
        let notice = await repository.recoveryNotice
        #expect(notice?.contains(backups[0].lastPathComponent) == true)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        #expect(try await repository.record(status(at: now), now: now).count == 1)
        #expect(try await repository.record(status(at: now.addingTimeInterval(60)), now: now.addingTimeInterval(60)).count == 2)
        #expect(await repository.recoveryNotice == notice)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(BGHistory.decodeLines(try Data(contentsOf: url)).samples.count == 2)
    }

    @Test func futureHistoryDoesNotBlockCurrentRecording() async throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let future = BGHistorySample(status: status(at: now.addingTimeInterval(3600)))
        try BGHistory.encodeLines([future]).write(to: url)
        let repository = HistoryRepository(url: url)
        #expect(try await repository.load(now: now).isEmpty)
        let recorded = try await repository.record(status(at: now), now: now)
        #expect(recorded.count == 1)
        #expect(recorded.first?.timestamp == now)
    }

    @Test func clockCorrectionAlsoRepairsAlreadyCachedHistory() async throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let repository = HistoryRepository(url: url)
        let wrongTime = now.addingTimeInterval(7200)
        #expect(try await repository.record(status(at: wrongTime), now: wrongTime).count == 1)
        let recorded = try await repository.record(status(at: now), now: now)
        #expect(recorded.count == 1)
        #expect(recorded.first?.timestamp == now)
        #expect(BGHistory.decodeLines(try Data(contentsOf: url)).samples == recorded)
    }

    @Test func legacyArrayIsMigratedOnceToLines() async throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("history.json")
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let old = BGHistorySample(status: status(at: now.addingTimeInterval(-120)))
        try BGJSON.encoder().encode([old]).write(to: legacy)
        let repository = HistoryRepository(url: url, legacyURL: legacy)
        #expect(try await repository.load(now: now) == [old])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(BGHistory.decodeLines(try Data(contentsOf: url)).samples == [old])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func recordingAppendsOneLineAndSkipsTruncatedTail() async throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let repository = HistoryRepository(url: url)
        _ = try await repository.record(status(at: now), now: now)
        let first = try Data(contentsOf: url)
        _ = try await repository.record(status(at: now.addingTimeInterval(60)), now: now.addingTimeInterval(60))
        let second = try Data(contentsOf: url)
        // The first line stays byte-identical; only one line was appended.
        #expect(second.prefix(first.count) == first)
        #expect(BGHistory.decodeLines(second).lineCount == 2)

        // A crash mid-write leaves a partial line; the next load drops it.
        var damaged = second; damaged.append(Data("{\"percent\":".utf8))
        try damaged.write(to: url)
        let reloaded = HistoryRepository(url: url)
        #expect(try await reloaded.load(now: now.addingTimeInterval(60)).count == 2)
        #expect(BGHistory.decodeLines(try Data(contentsOf: url)).endsCleanly)
    }

    @Test func pruningPrecedesIntervalCheckWithoutAdmittingStaleStatus() {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let old = BGHistorySample(status: status(at: now.addingTimeInterval(-BGHistory.retention - 60)))
        let future = BGHistorySample(status: status(at: now.addingTimeInterval(3600)))
        #expect(BGHistory.recording(status(at: now.addingTimeInterval(-120)), in: [old, future], now: now).isEmpty)
        #expect(BGHistory.recording(status(at: now), in: [old, future], now: now).count == 1)
    }
}
