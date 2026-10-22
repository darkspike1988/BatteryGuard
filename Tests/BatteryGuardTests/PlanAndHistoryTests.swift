import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct PlanAndHistoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func temporaryPauseRestoresOriginalProfileAtDeadline() {
        var c = BGProfile.desk.applying(to: BGConfig())
        c.pauseUntil = now.addingTimeInterval(3600)
        #expect(!c.effective(at: now).enabled)
        #expect(c.effective(at: now.addingTimeInterval(3600)).enabled)
        #expect(c.effective(at: now.addingTimeInterval(3600)).upperLimit == 50)
        #expect(c.removingExpiredPlans(at: now.addingTimeInterval(3600)).pauseUntil == nil)
    }

    @Test func travelWindowIsBounded() {
        var c = BGConfig()
        c.travelReadyAt = now.addingTimeInterval(12 * 3600)
        #expect(!c.effective(at: now).chargeToFullOnce)
        #expect(c.effective(at: now.addingTimeInterval(9 * 3600)).chargeToFullOnce)
        #expect(c.effective(at: now.addingTimeInterval(12 * 3600)).chargeToFullOnce)
        #expect(!c.effective(at: now.addingTimeInterval(13 * 3600)).chargeToFullOnce)
    }

    @Test func nativeAndPauseDoNotPretendToExecuteTravel() {
        var c = BGConfig(); c.travelReadyAt = now.addingTimeInterval(3600)
        c.mode = .native
        #expect(!c.effective(at: now).chargeToFullOnce)
        c.mode = .auto; c.pauseUntil = now.addingTimeInterval(7200)
        #expect(!c.effective(at: now).chargeToFullOnce)
        #expect(c.travelReadyAt != nil)
    }

    @Test func manualFullChargeExpiresWithoutUI() {
        var c = BGConfig()
        c.chargeToFullOnce = true
        c.fullChargeUntil = now.addingTimeInterval(8 * 3600)
        #expect(c.effective(at: now).chargeToFullOnce)
        #expect(!c.effective(at: now.addingTimeInterval(8 * 3600)).chargeToFullOnce)
    }

    @Test func scheduledTravelStillHonorsHeat() {
        var c = BGConfig()
        c.heatProtectionCelsius = 40
        c.travelReadyAt = now.addingTimeInterval(3600)
        var b = BatteryInfo(); b.percent = 70; b.pluggedIn = true; b.temperatureCelsius = 44
        let result = ControllerLogic.evaluate(config: c.effective(at: now), battery: b,
                                              previousDecision: nil, hasChargeControl: true, hasDischargeControl: true)
        #expect(!result.chargingEnabled)
        #expect(result.heatProtectionActive)
    }

    @Test func profilePreservesOtherChoices() {
        var c = BGConfig()
        c.mode = .auto
        c.heatProtectionCelsius = 38
        c.travelReadyAt = now.addingTimeInterval(3600)
        let next = BGProfile.mobile.applying(to: c)
        #expect(next.lowerLimit == 85 && next.upperLimit == 90)
        #expect(next.mode == .auto)
        #expect(next.heatProtectionCelsius == 38)
        #expect(next.travelReadyAt == c.travelReadyAt)
    }

    @Test func plansSurviveConfigRoundTripAndLegacyDefaults() throws {
        var c = BGConfig()
        c.pauseUntil = now; c.travelReadyAt = now; c.fullChargeUntil = now
        let decoded = try BGJSON.decoder().decode(BGConfig.self, from: BGJSON.encoder().encode(c))
        #expect(decoded == c)
        let legacy = try BGJSON.decoder().decode(BGConfig.self, from: Data("{\"upperLimit\":80}".utf8))
        #expect(legacy.pauseUntil == nil && legacy.travelReadyAt == nil && legacy.fullChargeUntil == nil)
    }

    @Test func unknownExplicitModeFallsBackToObservation() throws {
        let unknown = try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"mode":"future-active-mode"}"#.utf8))
        #expect(unknown.mode == .native)
        let legacy = try BGJSON.decoder().decode(BGConfig.self, from: Data("{}".utf8))
        #expect(legacy.mode == .auto)
        #expect(throws: (any Error).self) {
            try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"mode":123}"#.utf8))
        }
    }

    @Test func historyRejectsStaleFutureAndDuplicates() {
        var s = BGStatus(); s.updatedAt = now
        let once = BGHistory.recording(s, in: [], now: now)
        #expect(once.count == 1)
        #expect(BGHistory.recording(s, in: once, now: now) == once)
        s.updatedAt = now.addingTimeInterval(-61)
        #expect(BGHistory.recording(s, in: [], now: now).isEmpty)
        s.updatedAt = now.addingTimeInterval(6)
        #expect(BGHistory.recording(s, in: [], now: now).isEmpty)
    }

    @Test func historyRetentionAndCSV() {
        var s = BGStatus()
        s.updatedAt = now.addingTimeInterval(-BGHistory.retention - 60)
        let old = BGHistorySample(status: s)
        s.updatedAt = now; s.percent = 80; s.watts = -12.5
        let recent = BGHistory.recording(s, in: [old], now: now)
        #expect(recent.count == 1)
        #expect(recent.first?.timestamp == now)
        let csv = BGHistory.csv(recent)
        #expect(csv.contains(",80,,-12.5,"))
        #expect(csv.split(separator: "\n").count == 2)
        #expect(csv.split(separator: "\n").allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 8 })
    }

    @Test func dischargeCurrentSupportsBothRegistryWidths() {
        #expect(BatteryReader.signedAmperage(1500) == 1500)
        #expect(BatteryReader.signedAmperage(UInt64(UInt32(bitPattern: -1200))) == -1200)
        #expect(BatteryReader.signedAmperage(UInt64(bitPattern: -1200)) == -1200)
    }

    @Test func statusRemainsCompatibleWithOlderDaemon() throws {
        var status = BGStatus(); status.nativeChargeLimit = nil
        let encoded = try BGJSON.encoder().encode(status)
        let decoded = try BGJSON.decoder().decode(BGStatus.self, from: encoded)
        #expect(decoded.nativeChargeLimit == nil)
    }

    @Test func agingExposureWeightsTimeByTemperatureAndChargeBand() {
        #expect(abs(BGAgingExposure.temperatureFactor(celsius: 25) - 1) < 1e-9)
        #expect(abs(BGAgingExposure.temperatureFactor(celsius: 35) - 2.14) < 0.02)
        #expect(abs(BGAgingExposure.temperatureFactor(celsius: 45) - 4.35) < 0.05)
        #expect(BGAgingExposure.Band.of(percent: 50) == .low)
        #expect(BGAgingExposure.Band.of(percent: 60) == .middle)
        #expect(BGAgingExposure.Band.of(percent: 80) == .high)
        #expect(BGAgingExposure.Band.of(percent: 100) == .full)

        var s = BGStatus()
        func sample(_ offset: Double, percent: Int, temperature: Double?) -> BGHistorySample {
            s.updatedAt = now.addingTimeInterval(offset); s.percent = percent; s.temperatureCelsius = temperature
            return BGHistorySample(status: s)
        }
        let samples = [
            sample(0, percent: 50, temperature: 25),
            sample(60, percent: 85, temperature: 35),
            sample(120, percent: 85, temperature: nil),
            sample(180, percent: 85, temperature: 35),
            sample(3600, percent: 85, temperature: 35), // gap: not bridged
            sample(3660, percent: 85, temperature: 35),
        ]
        let exposure = BGAgingExposure.evaluate(samples)
        #expect(exposure.observedSeconds == 240)
        #expect(exposure.seconds[.low] == 60 && exposure.seconds[.high] == 180)
        #expect(exposure.secondsWithoutTemperature == 60)
        let hot = BGAgingExposure.temperatureFactor(celsius: 35)
        #expect(abs((exposure.weightedSeconds[.high] ?? 0) - (120 * hot + 60)) < 1e-6)
        #expect(abs((exposure.highChargeShare ?? 0) - 0.75) < 1e-9)
        #expect(BGAgingExposure.evaluate([]).averageTemperatureFactor == nil)
    }

    @Test func coldChargingWarnsOncePerEpisode() {
        var policy = BGColdChargingPolicy()
        let steps: [(Double?, Bool, Bool)] = [
            (8, false, false), (8, true, true), (7, true, false), (11, true, false),
            (9, true, false), (12, true, false), (9, true, true), (nil, true, false),
        ]
        for (temperature, charging, expected) in steps {
            let warned = policy.shouldWarn(temperatureCelsius: temperature, charging: charging)
            #expect(warned == expected)
        }
    }

    @Test func significantLimitChangesStartASettlingPeriod() {
        var change = BGLimitChange(upperLimit: 80)
        #expect(!change.isSettling(at: now))
        change = change.observing(upperLimit: 75, at: now)
        #expect(change.changedAt == nil && change.upperLimit == 80)
        change = change.observing(upperLimit: 70, at: now)
        #expect(change.changedAt == now && change.upperLimit == 70)
        #expect(change.isSettling(at: now.addingTimeInterval(27 * 86400)))
        #expect(!change.isSettling(at: now.addingTimeInterval(29 * 86400)))
        let decoded = try? BGJSON.decoder().decode(BGLimitChange.self, from: BGJSON.encoder().encode(change))
        #expect(decoded == change)
    }

    @Test func historyLinesRoundTripAndSkipDamagedLines() throws {
        var s = BGStatus(); s.percent = 70
        let samples = [0.0, 60, 120].map { offset -> BGHistorySample in
            s.updatedAt = now.addingTimeInterval(offset); return BGHistorySample(status: s)
        }
        var data = try BGHistory.encodeLines(samples)
        let clean = BGHistory.decodeLines(data)
        #expect(clean.samples == samples && clean.lineCount == 3 && clean.invalidLines == 0 && clean.endsCleanly)
        data.append(Data("{\"timestamp\":".utf8))
        let damaged = BGHistory.decodeLines(data)
        #expect(damaged.samples == samples && damaged.invalidLines == 1 && !damaged.endsCleanly)
        #expect(BGHistory.isAppend(samples, to: Array(samples.dropLast())))
        #expect(BGHistory.isAppend(Array(samples.dropFirst()), to: Array(samples.dropLast())))
        #expect(!BGHistory.isAppend(samples, to: samples))
        #expect(!BGHistory.isAppend(Array(samples.prefix(2)), to: [samples[0], samples[2]]))
    }

    @Test func statusFromNewerDaemonStaysReadable() throws {
        var status = BGStatus(); status.percent = 64; status.state = .holding
        var json = try JSONSerialization.jsonObject(with: BGJSON.encoder().encode(status)) as! [String: Any]
        json["state"] = "futureState"
        json["measurements"] = ["schemaVersion": 2, "values": []]
        json["newField"] = 1
        json.removeValue(forKey: "smcKeysDetected")
        let decoded = try BGJSON.decoder().decode(BGStatus.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.percent == 64)
        #expect(decoded.state == .unsupported)
        #expect(decoded.measurements == nil)
        #expect(decoded.smcKeysDetected.isEmpty)
        #expect(abs(decoded.updatedAt.timeIntervalSince(status.updatedAt)) < 1)
        let empty = try BGJSON.decoder().decode(BGStatus.self, from: Data("{}".utf8))
        #expect(empty.updatedAt == .distantPast)
    }

    @Test func summaryDoesNotBridgeSleepGaps() {
        var s = BGStatus(); s.percent = 95; s.temperatureCelsius = 42; s.state = .holding
        let samples = [0.0, 60, 7200, 7260].map { offset in
            s.updatedAt = now.addingTimeInterval(offset)
            return BGHistorySample(status: s)
        }
        let summary = BGHistory.summary(samples)
        #expect(summary.observedSeconds == 120)
        #expect(summary.highChargeSeconds == 120)
        #expect(summary.hotSeconds == 120)
        #expect(summary.heldSeconds == 120)
        #expect(summary.peakTemperature == 42)
    }
}
