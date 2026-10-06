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
    @Test func oversizedAndSymlinkFilesAreRejectedWithoutMutation() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("capacity-days.json")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 64_000_000)
        try handle.close()
        do { _ = try await CapacityTrendRepository(url: url).load(now: now); Issue.record("Oversized file accepted") }
        catch { }
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue == 64_000_000)
        try FileManager.default.removeItem(at: url)
        let target = dir.appendingPathComponent("original.json")
        try Data("[]".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        do { _ = try await CapacityTrendRepository(url: url).load(now: now); Issue.record("Symlink accepted") }
        catch { }
        #expect(try Data(contentsOf: target) == Data("[]".utf8))
    }

    @Test func unreadableParentMustNotBeCachedAsMissing() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("capacity-days.json")
        try Data("[]".utf8).write(to: url)
        let repository = CapacityTrendRepository(url: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        do { _ = try await repository.load(now: now); Issue.record("Unreadable parent treated as missing") }
        catch { }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        #expect(try await repository.load(now: now).isEmpty)
        #expect(try Data(contentsOf: url) == Data("[]".utf8))
    }

}
