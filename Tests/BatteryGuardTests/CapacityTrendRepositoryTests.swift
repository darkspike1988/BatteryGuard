import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct CapacityTrendRepositoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func validDataPersistsPrivatelyAndDuplicateDoesNotIncreaseCount() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("capacity-days.json")
        var status = BGStatus(); status.updatedAt = now; status.maxCapacityMah = 4800; status.designCapacityMah = 5000
        let repository = CapacityTrendRepository(url: url)
        let first = try await repository.record(status, now: now)
        #expect(first.count == 1 && first[0].count == 1)
        #expect(try await repository.record(status, now: now) == first)
        let restored = try await CapacityTrendRepository(url: url).load(now: now)
        #expect(restored == first)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func damagedFileIsNeverOverwrittenAndMissingValuesCreateNoFile() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("capacity-days.json")
        let broken = Data("broken-original".utf8)
        try broken.write(to: url)
        var status = BGStatus(); status.updatedAt = now; status.maxCapacityMah = 4800; status.designCapacityMah = 5000
        do {
            _ = try await CapacityTrendRepository(url: url).record(status, now: now)
            Issue.record("Corrupt file must fail rather than reset")
        } catch { }
        #expect(try Data(contentsOf: url) == broken)
        let emptyURL = dir.appendingPathComponent("empty.json")
        var empty = BGStatus(); empty.updatedAt = now
        #expect(try await CapacityTrendRepository(url: emptyURL).record(empty, now: now).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: emptyURL.path))
    }
}
