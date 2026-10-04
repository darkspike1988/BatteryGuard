import Foundation
import Testing
import BatteryGuardShared

struct ConfigFileTests {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var config = BGConfig(); config.upperLimit = 40
        try BGJSON.encoder().encode(config).write(to: url)
        return url
    }

    @Test func concurrentUpdatesDoNotLoseChanges() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { try BGConfigFile.update(at: url) { $0.upperLimit += 1 } }
            }
            try await group.waitForAll()
        }
        #expect(try BGConfigFile.read(at: url).upperLimit == 48)
    }

    @Test func invalidConfigAndSymlinkAreNeverOverwritten() throws {
        let url = try fixture()
        let link = url.appendingPathExtension("link")
        defer { try? FileManager.default.removeItem(at: link); try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(throws: (any Error).self) { try BGConfigFile.update(at: link) { $0.enabled = false } }
        #expect(try BGConfigFile.read(at: url).enabled)
        let invalid = Data("broken".utf8)
        try invalid.write(to: url)
        #expect(throws: (any Error).self) { try BGConfigFile.update(at: url) { $0.enabled = false } }
        #expect(try Data(contentsOf: url) == invalid)
    }
}
