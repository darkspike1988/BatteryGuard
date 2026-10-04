import Foundation
import Darwin
import Testing
@testable import BatteryGuardShared

struct ConfigRecoveryTests {
    private func fixture() throws -> (URL, URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("config.json"), directory.appendingPathComponent("config.backup.json"))
    }

    @Test func validConfigCreatesSanitizedBackup() throws {
        let (directory, configURL, backupURL) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = BGConfig(); config.upperLimit = 999
        let original = try BGJSON.encoder().encode(config)
        try original.write(to: configURL)
        let result = try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        #expect(!result.recovered)
        #expect(try Data(contentsOf: configURL) == original)
        let backup = try BGJSON.decoder().decode(BGConfig.self, from: Data(contentsOf: backupURL))
        #expect(backup.upperLimit == 100)
        let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
    }

    @Test func corruptConfigUsesDisabledBackupAndQuarantinesExactBytes() throws {
        let (directory, configURL, backupURL) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = BGConfig(); config.lowerLimit = 55; config.upperLimit = 60
        config.chargeToFullOnce = true; config.fullChargeUntil = Date().addingTimeInterval(1000)
        config.travelReadyAt = Date().addingTimeInterval(1000)
        try BGJSON.encoder().encode(config).write(to: configURL)
        _ = try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        let corrupt = Data("{\"enabled\":true,\"upperLimit\":\"wrong type\"}".utf8)
        try corrupt.write(to: configURL)
        let result = try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        #expect(result.recovered && result.usedBackup)
        let quarantine = try #require(result.quarantinePath)
        #expect(try Data(contentsOf: URL(fileURLWithPath: quarantine)) == corrupt)
        let restored = try BGConfigFile.read(at: configURL)
        #expect(!restored.enabled && restored.upperLimit == 60 && restored.lowerLimit == 55)
        #expect(!restored.chargeToFullOnce && restored.travelReadyAt == nil && restored.fullChargeUntil == nil)
        #expect(result.message?.contains("deaktiviert") == true)
    }

    @Test func missingBackupRestoresDisabledDefaults() throws {
        let (directory, configURL, backupURL) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: configURL)
        let result = try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        #expect(result.recovered && !result.usedBackup)
        let restored = try BGConfigFile.read(at: configURL)
        #expect(!restored.enabled && restored.upperLimit == BGConfig().upperLimit)
    }

    @Test func corruptRegularBackupCannotReactivateProtection() throws {
        let (directory, configURL, backupURL) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken config".utf8).write(to: configURL)
        try Data("broken backup".utf8).write(to: backupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backupURL.path)
        let result = try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        #expect(result.recovered && !result.usedBackup)
        #expect(try BGConfigFile.read(at: configURL).enabled == false)
        #expect(try Data(contentsOf: backupURL) == Data("broken backup".utf8))
    }

    @Test func symlinkConfigIsNotRepairedAndTargetIsUnchanged() throws {
        let (directory, configURL, backupURL) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let original = Data("broken".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(atPath: configURL.path, withDestinationPath: target.path)
        #expect(throws: (any Error).self) {
            try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        }
        #expect(try Data(contentsOf: target) == original)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }

    @Test func missingConfigAndSymlinkBackupDoNotAuthorizeRepair() throws {
        let (directory, configURL, backupURL) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) {
            try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        }
        let original = Data("broken".utf8)
        try original.write(to: configURL)
        let target = directory.appendingPathComponent("target.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: backupURL.path, withDestinationPath: target.path)
        #expect(throws: (any Error).self) {
            try BGConfigRecovery.prepare(configURL: configURL, backupURL: backupURL, requireRoot: false)
        }
        #expect(try Data(contentsOf: configURL) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 3)
    }
}
