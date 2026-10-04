import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct HistoryRepositoryTests {
    private func fixture() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("history.json"))
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
        #expect(try BGJSON.decoder().decode([BGHistorySample].self, from: Data(contentsOf: url)).count == 2)
    }

    @Test func futureHistoryDoesNotBlockCurrentRecording() async throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let future = BGHistorySample(status: status(at: now.addingTimeInterval(3600)))
        try BGJSON.encoder().encode([future]).write(to: url)
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
        #expect(try BGJSON.decoder().decode([BGHistorySample].self, from: Data(contentsOf: url)) == recorded)
    }

    @Test func pruningPrecedesIntervalCheckWithoutAdmittingStaleStatus() {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let old = BGHistorySample(status: status(at: now.addingTimeInterval(-BGHistory.retention - 60)))
        let future = BGHistorySample(status: status(at: now.addingTimeInterval(3600)))
        #expect(BGHistory.recording(status(at: now.addingTimeInterval(-120)), in: [old, future], now: now).isEmpty)
        #expect(BGHistory.recording(status(at: now), in: [old, future], now: now).count == 1)
    }
}
