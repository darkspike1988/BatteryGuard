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
        #expect(c.effective(at: now.addingTimeInterval(3600)).upperLimit == 60)
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
        c.mode = .pendulum
        c.heatProtectionCelsius = 38
        c.travelReadyAt = now.addingTimeInterval(3600)
        let next = BGProfile.mobile.applying(to: c)
        #expect(next.lowerLimit == 85 && next.upperLimit == 90)
        #expect(next.mode == .pendulum)
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
