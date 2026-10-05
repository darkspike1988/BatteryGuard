import Foundation
import Testing
import BatteryGuardShared

struct DiagnosticAnalysisTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func snapshot(at date: Date, maximum: Double = 4800, source: BGMeasurementSource = .rawMaxCapacity) -> BGBatteryMeasurements {
        let max = BGMeasurement(.fullChargeCapacity, value: maximum, source: source, sampledAt: date)
        let design = BGMeasurement(.designCapacity, value: 5000, source: .designCapacity, sampledAt: date)
        return BGBatteryMeasurements(values: [max, design,
            BGBatteryMeasurements.capacityRatio(maximum: max, design: design),
            BGMeasurement(.chargePercent, value: 80, source: .powerSources, sampledAt: date)])
    }

    @Test func cpuIsIntervalNormalizedAndNeedsValidTicks() {
        #expect(BGResourceMath.cpuLoad(previous: [10, 10, 10, 10], current: [20, 20, 80, 20]) == 30)
        #expect(BGResourceMath.cpuLoad(previous: [0, 0, 0, 0], current: [0, 0, 10, 0]) == 0)
        #expect(BGResourceMath.cpuLoad(previous: [10, 0, 0, 0], current: [9, 0, 0, 0]) == nil)
        #expect(BGResourceMath.cpuLoad(previous: [0, 0, 0, 0], current: [0, 0, 0, 0]) == nil)
        #expect(BGResourceMath.cpuLoad(previous: [], current: []) == nil)
    }

    @Test func dailyAggregationCountsOnlyFreshSpacedObservations() {
        var days = BGCapacityTrend.recording(snapshot(at: now), in: [], osVersion: "27.0", at: now)
        #expect(days.count == 1 && days[0].count == 1 && days[0].mean == 96)
        days = BGCapacityTrend.recording(snapshot(at: now), in: days, osVersion: "27.0", at: now)
        #expect(days[0].count == 1)
        days = BGCapacityTrend.recording(snapshot(at: now.addingTimeInterval(60), maximum: 4900), in: days,
                                        osVersion: "27.0", at: now.addingTimeInterval(60))
        #expect(days[0].count == 2 && days[0].mean == 97 && days[0].minimum == 96 && days[0].maximum == 98)
        let stale = BGCapacityTrend.recording(snapshot(at: now), in: days, osVersion: "27.0", at: now.addingTimeInterval(200))
        #expect(stale == days)
    }

    @Test func utcDaysAndTrendRequireComparableSourcesAndOS() {
        var days: [BGCapacityDay] = []
        for index in 0..<3 {
            let date = now.addingTimeInterval(Double(index) * 86400)
            days = BGCapacityTrend.recording(snapshot(at: date, maximum: 4800 - Double(index) * 10), in: days,
                                            osVersion: "27.0", at: date)
        }
        #expect(days.count == 3)
        #expect(abs((BGCapacityTrend.change(days) ?? 0) + 0.4) < 0.001)
        let next = now.addingTimeInterval(3 * 86400)
        let changedSource = BGCapacityTrend.recording(snapshot(at: next, source: .nominalCapacity), in: days,
                                                      osVersion: "27.0", at: next)
        #expect(BGCapacityTrend.change(changedSource) == nil)
        let changedOS = BGCapacityTrend.recording(snapshot(at: next), in: days, osVersion: "27.1", at: next)
        #expect(BGCapacityTrend.change(changedOS) == nil)
        #expect(BGCapacityTrend.change(Array(days.prefix(2))) == nil)
        #expect(days.allSatisfy { $0.day.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) == 0 })
    }

    @Test func retentionAndCorruptionAreBounded() {
        let old = BGCapacityTrend.recording(snapshot(at: now), in: [], osVersion: "27.0", at: now)
        #expect(BGCapacityTrend.recording(BGBatteryMeasurements(values: []), in: old,
                                          osVersion: "27.0", at: now.addingTimeInterval(366 * 86400)).isEmpty)
        var broken = old[0]; broken.count = 0
        #expect(!broken.isValid)
        #expect(BGCapacityTrend.recording(snapshot(at: now), in: [], osVersion: "/Users/private", at: now).isEmpty)
    }

    @Test func staleOrMissingDataNeverGenerateThermalOrLoadClaims() {
        let measures = BGBatteryMeasurements(values: [BGMeasurement(.cpuLoad, value: 99, source: .machCPU, sampledAt: now)])
        let old = BGSystemSnapshot(sampledAt: now.addingTimeInterval(-61), thermalState: .critical, measurements: measures)
        let issues = BGDiagnosticRules.evaluate(battery: BGBatteryMeasurements(values: []), system: old, at: now)
        #expect(issues.contains(.batteryDataUnavailable) && issues.contains(.systemDataUnavailable))
        #expect(!issues.contains(.thermalCritical) && !issues.contains(.cpuBusy))
        let fresh = BGSystemSnapshot(sampledAt: now, thermalState: .critical, measurements: measures)
        let current = BGDiagnosticRules.evaluate(battery: snapshot(at: now), system: fresh, at: now)
        #expect(current.contains(.thermalCritical) && current.contains(.cpuBusy))
        #expect(current.contains(.capacityIsEstimate))
    }

    @Test func whitelistedExportOmitsPrivateStatusAndStaleNumbers() throws {
        let secret = "token-/Users/Alice-serial-travel-private"
        var status = BGStatus(); status.updatedAt = now; status.message = secret
        status.configurationNotice = secret; status.daemonVersion = secret; status.smcKeysDetected = [secret]
        status.measurements = snapshot(at: now.addingTimeInterval(-61))
        let system = BGSystemSnapshot(sampledAt: now, thermalState: .nominal, measurements: BGBatteryMeasurements(values: []), modelIdentifier: secret)
        let report = BGDiagnosticReport(appVersion: secret, daemonVersion: secret, battery: status, system: system, at: now)
        let bytes = try BGJSON.encoder().encode(report)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains(secret) && !text.contains("configurationNotice") && !text.contains("smcKeysDetected"))
        #expect(report.appVersion == "unknown" && report.daemonVersion == "unknown")
        #expect(report.system?.modelIdentifier == nil)
        #expect(report.battery.values.allSatisfy { $0.value == nil })
        #expect(try BGJSON.decoder().decode(BGDiagnosticReport.self, from: bytes) == report)
    }

    @Test func narrowCycleReferenceDoesNotGuessUnknownModels() {
        #expect(BGBatteryCycleReference.maximumCycles(model: "MacBookPro18,3") == 1000)
        #expect(BGBatteryCycleReference.maximumCycles(model: "Mac999,1") == nil)
        #expect(BGBatteryCycleReference.maximumCycles(model: nil) == nil)
    }

    @Test func dailyDataRoundTripPreservesSourceAndRange() throws {
        let days = BGCapacityTrend.recording(snapshot(at: now, maximum: 5100), in: [], osVersion: "27.0", at: now)
        let decoded = try BGJSON.decoder().decode([BGCapacityDay].self, from: BGJSON.encoder().encode(days))
        #expect(decoded == days && decoded[0].mean == 102 && decoded[0].isValid)
    }
}
