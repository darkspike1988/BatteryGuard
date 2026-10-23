import Testing
import Foundation
import BatteryGuardShared
@testable import BatteryGuard
@testable import batteryguardd

struct Analysis09Tests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func sample(_ percent: Int, temperature: Double?, watts: Double?) -> BGHistorySample {
        var status = BGStatus()
        status.updatedAt = now
        status.percent = percent
        status.temperatureCelsius = temperature
        status.watts = watts
        return BGHistorySample(status: status)
    }

    func day(_ offset: Double, ratio: Double, cycles: Double) -> BGCapacityDay {
        BGCapacityDay(day: now.addingTimeInterval(offset * 86_400), maximumSource: .rawMaxCapacity,
                      designSource: .fullChargeCapacity, designCapacity: 6000, osVersion: "27.0", count: 1,
                      ratioSum: ratio, minimum: ratio, maximum: ratio, firstSampledAt: now, lastSampledAt: now,
                      cycleSum: cycles, cycleSamples: 1)
    }

    @Test func lifetimeAnalysisUsesOnlyMeasuredValues() {
        let samples = [sample(10, temperature: 20, watts: -10), sample(50, temperature: 30, watts: 20),
                       sample(90, temperature: 40, watts: nil), sample(85, temperature: nil, watts: -6)]
        let analysis = BGLifetimeAnalysis.analyze(samples: samples, capacityDays: [day(-60, ratio: 0.95, cycles: 100), day(0, ratio: 0.93, cycles: 130)])
        #expect(analysis.temperatureMinimum == 20 && analysis.temperatureMaximum == 40 && analysis.temperatureMean == 30)
        #expect(analysis.bands.low == 0.25 && analysis.bands.high == 0.5 && analysis.bands.middle == 0.25)
        #expect(analysis.averageChargeWatts == 20 && analysis.averageDischargeWatts == 8)
        #expect(analysis.capacityFirst == 95 && analysis.capacityLast == 93)
        #expect(analysis.capacityChangePerMonth.map { abs($0 + 1.0147) < 0.01 } == true)
        #expect(analysis.cyclesPerMonth.map { abs($0 - 15.22) < 0.05 } == true)
        let short = BGLifetimeAnalysis.analyze(samples: [], capacityDays: [day(-10, ratio: 0.95, cycles: 1), day(0, ratio: 0.94, cycles: 2)])
        #expect(short.capacityChangePerMonth == nil && short.cyclesPerMonth == nil && short.temperatureMean == nil)
    }

    @Test func bluetoothParserReadsOnlyReportedLevels() {
        let json = #"""
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro":{"device_batteryLevelLeft":"70%","device_batteryLevelRight":"72 %","device_batteryLevelCase":"40%","device_minorType":"Headphones"}},
          {"MX Keys":{"device_minorType":"Keyboard"}},
          {"Magic Mouse":{"device_batteryLevelMain":"55%"}},
          {"Kaputt":{"device_batteryLevelMain":"140%"}}
        ]}]}
        """#
        let devices = DeviceBatteryReader.parseBluetooth(Data(json.utf8))
        #expect(devices.map(\.name) == ["AirPods Pro", "Magic Mouse"])
        #expect(devices[0].levels == ["Links": 70, "Rechts": 72, "Case": 40] && devices[1].levels == ["": 55])
        #expect(DeviceBatteryReader.parseBluetooth(Data("{}".utf8)).isEmpty)
    }

    @Test func managedPolicyParsesTypedKeysAndEnforcesValues() {
        let policy = BGManagedPolicy.parse(["LockSettings": true, "UpperLimit": 70, "LowerLimit": 60,
                                            "Mode": "systemLimit", "ProtectionEnabled": true, "Unbekannt": 1])
        #expect(policy == BGManagedPolicy(lockSettings: true, upperLimit: 70, lowerLimit: 60, mode: .systemLimit, protectionEnabled: true))
        #expect(BGManagedPolicy.parse(["UpperLimit": true, "Mode": "direct"]) == nil)
        #expect(BGManagedPolicy.parse([:]) == nil)
        var config = BGConfig(); config.enabled = false; config.upperLimit = 95
        let enforced = policy!.apply(to: config)
        #expect(enforced.upperLimit == 70 && enforced.lowerLimit == 60 && enforced.mode == .systemLimit && enforced.enabled)
    }

    @Test func lockedPolicyRejectsUserWritesButAllowsQueries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        var desired = BGConfig(); desired.upperLimit = 90
        let locked = { BGManagedPolicy(lockSettings: true) }
        #expect(throws: (any Error).self) {
            try ConfigServer.apply(BGConfigRequest(baseline: BGConfig(), desired: desired), peerUID: 501, consoleUID: 501,
                                   configURL: url, managedPolicy: locked)
        }
        let query = try ConfigServer.apply(BGConfigRequest(baseline: BGConfig(), desired: desired, queryOnly: true),
                                           peerUID: 501, consoleUID: 501, configURL: url, managedPolicy: locked)
        #expect(query.upperLimit == BGConfig().upperLimit)
        let unlocked = try ConfigServer.apply(BGConfigRequest(baseline: BGConfig(), desired: desired), peerUID: 501, consoleUID: 501,
                                              configURL: url, managedPolicy: { BGManagedPolicy(upperLimit: 70) })
        #expect(unlocked.upperLimit == 90)
    }

    @Test func backupKeepsPersistentSettingsOnly() throws {
        var config = BGConfig()
        config.upperLimit = 70; config.lowerLimit = 65; config.mode = .systemLimit; config.coldProtectionCelsius = 5
        config.pauseUntil = now.addingTimeInterval(600); config.travelReadyAt = now.addingTimeInterval(3600)
        config.scheduleHistory = [BGScheduleRun(taskID: UUID(), occurrenceAt: now, executedAt: now, resultString: "x")]
        let backup = BGSettingsBackup(config: config, preferences: ["bg.accentColor": .string("green"), "other": .bool(true)], createdAt: now)
        #expect(backup.config.pauseUntil == nil && backup.config.travelReadyAt == nil && backup.config.scheduleHistory.isEmpty)
        #expect(backup.preferences.keys.sorted() == ["bg.accentColor"])
        let decoded = try BGSettingsBackup.decode(BGJSON.encoder().encode(backup))
        var current = BGConfig(); current.pauseUntil = now.addingTimeInterval(60)
        let restored = current.applyingPortable(from: decoded.config)
        #expect(restored.upperLimit == 70 && restored.mode == .systemLimit && restored.coldProtectionCelsius == 5)
        #expect(restored.pauseUntil == current.pauseUntil)
        #expect(throws: (any Error).self) { try BGSettingsBackup.decode(Data(count: BGSettingsBackup.maxBytes + 1)) }
        #expect(SettingsBackupView.isPortablePreference("bg.notifyHeat"))
        #expect(!SettingsBackupView.isPortablePreference("bg.apiToken") && !SettingsBackupView.isPortablePreference("bg.lastWeeklyReportAt"))
        #expect(BGPreferenceValue(true) == .bool(true) && BGPreferenceValue(3) == .int(3) && BGPreferenceValue(1.5) == .double(1.5))
    }

    @Test func historyCipherRoundTripsAndRejectsWrongKeys() throws {
        let cipher = try BGHistoryCipher(keyData: BGHistoryCipher.newKeyData())
        let sealed = try cipher.seal(Data("geheim".utf8))
        #expect(BGHistoryCipher.isEncrypted(sealed) && !sealed.contains(Data("geheim".utf8)))
        #expect(try cipher.open(sealed) == Data("geheim".utf8))
        #expect(try cipher.open(Data("klartext".utf8)) == Data("klartext".utf8))
        let other = try BGHistoryCipher(keyData: BGHistoryCipher.newKeyData())
        #expect(throws: (any Error).self) { try other.open(sealed) }
        #expect(throws: (any Error).self) { try BGHistoryCipher(keyData: Data(count: 16)) }
    }

    @Test func encryptedHistoryIsWrittenAndNeverTreatedAsCorruptWithoutKey() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let cipher = try BGHistoryCipher(keyData: BGHistoryCipher.newKeyData())
        var status = BGStatus(); status.updatedAt = Date(); status.percent = 77
        let writer = HistoryRepository(url: url, readCipher: { cipher }, writeCipher: { cipher })
        _ = try await writer.record(status)
        #expect(BGHistoryCipher.isEncrypted(try Data(contentsOf: url)))
        #expect(try await HistoryRepository(url: url, readCipher: { cipher }).load().first?.percent == 77)
        await #expect(throws: (any Error).self) { try await HistoryRepository(url: url).load() }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["history.json"])
    }
}
