import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct DiagnosticsExportTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func report(_ status: BGStatus, config: BGConfig = BGConfig(),
                        appVersion: String = "0.3.7", requiredDaemon: String = "0.3.7") -> DiagnosticsReport {
        DiagnosticsExport.build(config: config, status: status, appVersion: appVersion,
                                requiredDaemon: requiredDaemon,
                                macOSVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 1),
                                daemonActive: true, apiEnabled: true, controlAllowed: false, at: now)
    }

    @Test func exportContainsOnlyWhitelistedFieldsAndRejectsPersonalStrings() throws {
        let secret = "private-token-Alice-/Users/Alice/Documents-MacBook-serial"
        let identifier = UUID()
        var config = BGConfig()
        config.pauseUntil = now.addingTimeInterval(3600)
        config.travelReadyAt = now.addingTimeInterval(86400)
        config.fullChargeUntil = now.addingTimeInterval(7200)
        config.fullChargeRequestID = identifier
        config.travelRequestID = identifier
        config.specialChargePlan = BGSpecialChargePlan(requestID: identifier, kind: .hold, targetPercent: 75,
                                                       createdAt: now, expiresAt: now.addingTimeInterval(3600))
        config.heatProtectionCelsius = 42
        var status = BGStatus()
        status.updatedAt = now
        status.message = "Monitor-/Deckelschutz: " + secret
        status.state = .disabled
        status.configurationNotice = secret
        status.daemonVersion = secret
        status.smcKeysDetected = ["CHIE", "CHTE", "CHIE", secret, "CHLT", "CHTE " + secret,
                                  String(repeating: "x", count: 10000)]
        let exported = report(status, config: config, appVersion: secret, requiredDaemon: String(repeating: "1", count: 10000))
        let bytes = try DiagnosticsExport.data(for: exported)
        let text = String(decoding: bytes, as: UTF8.self)
        let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(object.keys) == Set([
            "appVersion", "requiredDaemon", "daemonVersion", "macOSVersion", "daemonActive", "statusFresh",
            "state", "smcKeysDetected", "usesNativeDesktopFallback", "enabled", "mode", "heatEnabled",
            "apiEnabled", "controlAllowed", "hasPause", "hasSpecialPlan", "hasTravelPlan"
        ]))
        #expect(!text.contains(secret))
        #expect(!text.contains(identifier.uuidString))
        #expect(!text.contains("updatedAt"))
        #expect(!text.contains("targetPercent"))
        #expect(!text.contains("1750000000"))
        #expect(!text.contains(String(repeating: "x", count: 100)))
        #expect(exported.appVersion == "unknown")
        #expect(exported.requiredDaemon == "unknown")
        #expect(exported.daemonVersion == "unknown")
        #expect(exported.smcKeysDetected == ["CHIE", "CHTE"])
        #expect(exported.usesNativeDesktopFallback)
        #expect(exported.hasPause && exported.hasSpecialPlan && exported.hasTravelPlan)
        #expect(exported.heatEnabled && exported.apiEnabled && !exported.controlAllowed)
        #expect(exported.macOSVersion == "15.4.1")
        #expect(try JSONDecoder().decode(DiagnosticsReport.self, from: bytes) == exported)
    }

    @Test func freshnessIncludesOnlyTheFiveSecondFutureAndSixtySecondPastWindow() {
        for (age, fresh) in [(-5.001, false), (-5.0, true), (0.0, true), (60.0, true), (60.001, false)] {
            var status = BGStatus()
            status.updatedAt = now.addingTimeInterval(-age)
            #expect(report(status).statusFresh == fresh)
        }
    }

    @Test func validVersionsAndAbsentPlansRemainSmallTypedValues() {
        var status = BGStatus()
        status.daemonVersion = "0.3.7"
        status.state = .holding
        let exported = report(status)
        #expect(exported.appVersion == "0.3.7")
        #expect(exported.requiredDaemon == "0.3.7")
        #expect(exported.daemonVersion == "0.3.7")
        #expect(exported.state == .holding)
        #expect(exported.mode == .auto)
        #expect(!exported.hasPause && !exported.hasSpecialPlan && !exported.hasTravelPlan)
        #expect(!exported.heatEnabled && !exported.usesNativeDesktopFallback)
        for invalid in ["1..2", ".1", "1.", "1.2.3.4.5", "1\nsecret", "1234567"] {
            #expect(report(status, appVersion: invalid).appVersion == "unknown")
        }
    }

    @Test func atomicExportReplacesOnlySelectedTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("diagnostics.json")
        let sibling = directory.appendingPathComponent("unselected.txt")
        try Data("old content".utf8).write(to: destination)
        let untouched = Data("unselected content".utf8)
        try untouched.write(to: sibling)
        let exported = report(BGStatus())
        try DiagnosticsExport.write(exported, to: destination)
        #expect(try Data(contentsOf: destination) == DiagnosticsExport.data(for: exported))
        #expect(try Data(contentsOf: sibling) == untouched)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == ["diagnostics.json", "unselected.txt"])
    }
}
