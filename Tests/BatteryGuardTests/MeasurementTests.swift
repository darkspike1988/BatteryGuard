import Foundation
import Testing
import BatteryGuardShared

struct MeasurementTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func missingAndInvalidAreNeverZero() {
        let missing = BGMeasurement(.batteryTemperature, value: nil, source: .registryTemperature, sampledAt: now)
        #expect(missing.value == nil && missing.quality == .unavailable)
        let invalid = BGMeasurement(.batteryTemperature, value: .nan, source: .registryTemperature, sampledAt: now)
        #expect(invalid.value == nil && invalid.quality == .invalid)
        let zero = BGMeasurement(.batteryPower, value: 0, source: .registryPower, sampledAt: now)
        #expect(zero.value == 0 && zero.quality == .reported)
    }

    @Test func freshnessIncludesKnownSensorAgeAndDoesNotInventIt() {
        let host = BGMeasurement(.batteryPower, value: 2, source: .registryPower, sampledAt: now)
        #expect(host.sensorUpdatedAt == nil)
        #expect(host.evaluated(at: now.addingTimeInterval(60)).value == 2)
        #expect(host.evaluated(at: now.addingTimeInterval(61)).quality == .stale)
        #expect(host.evaluated(at: now.addingTimeInterval(-6)).quality == .invalid)
        let oldSensor = BGMeasurement(.batteryPower, value: 2, source: .registryPower, sampledAt: now,
                                      sensorUpdatedAt: now.addingTimeInterval(-61))
        #expect(oldSensor.evaluated(at: now).value == nil)
        #expect(oldSensor.evaluated(at: now).quality == .stale)
    }

    @Test func ratioKeepsAbove100AndUsesOldestInput() {
        let max = BGMeasurement(.fullChargeCapacity, value: 5100, source: .rawMaxCapacity,
                                sampledAt: now.addingTimeInterval(-70))
        let design = BGMeasurement(.designCapacity, value: 5000, source: .designCapacity, sampledAt: now)
        let ratio = BGBatteryMeasurements.capacityRatio(maximum: max, design: design)
        #expect(ratio.value == 102)
        #expect(ratio.quality == .derived)
        #expect(ratio.evaluated(at: now).quality == .stale)
    }

    @Test func normalizedUnitsAndUnsignedDischargeCurrent() {
        for amps in [NSNumber(value: -1200), NSNumber(value: UInt32(bitPattern: -1200)),
                     NSNumber(value: UInt64(bitPattern: -1200))] {
            let sample = BGBatteryDiagnosticParser.parse(properties: ["Voltage": 12_000, "InstantAmperage": amps], sampledAt: now)
            #expect(sample.measurement(.batteryVoltage, at: now)?.value == 12)
            #expect(sample.measurement(.batteryCurrent, at: now)?.value == -1.2)
            #expect(abs((sample.measurement(.batteryPower, at: now)?.value ?? 0) + 14.4) < 0.001)
        }
    }

    @Test func parserRejectsBooleanAndDoesNotHideBrokenPrimaryCapacity() {
        let sample = BGBatteryDiagnosticParser.parse(properties: [
            "AppleRawMaxCapacity": -1, "DesignCapacity": 5000, "CycleCount": true,
            "BatteryData": ["FullChargeCapacity": 4800]], sampledAt: now)
        #expect(sample.measurement(.fullChargeCapacity, at: now)?.quality == .invalid)
        #expect(sample.measurement(.capacityRatio, at: now)?.value == nil)
        #expect(sample.measurement(.cycleCount, at: now)?.value == nil)
    }

    @Test func sourceFallbacksAreVisible() {
        let sample = BGBatteryDiagnosticParser.parse(properties: [
            "BatteryData": ["FullChargeCapacity": 5000, "DesignCapacity": 5100]], sampledAt: now,
            publicPercent: 75, fallbackTemperature: 30)
        #expect(sample.measurement(.fullChargeCapacity, at: now)?.source == .fullChargeCapacity)
        #expect(sample.measurement(.designCapacity, at: now)?.source == .nestedDesignCapacity)
        #expect(sample.measurement(.chargePercent, at: now)?.source == .powerSources)
        #expect(sample.measurement(.batteryTemperature, at: now)?.source == .smcTemperature)
    }

    @Test func legacyStatusIsExplicitAndUnitCompatible() throws {
        var s = BGStatus(); s.updatedAt = now; s.voltage = 12000; s.amperage = -1200
        s.healthPercent = 95
        let old = s.diagnosticMeasurements(at: now)
        #expect(old.measurement(.batteryVoltage, at: now)?.value == 12)
        #expect(old.measurement(.batteryVoltage, at: now)?.source == .legacyStatus)
        #expect(old.measurement(.capacityRatio, at: now)?.value == nil)
        s.measurements = old
        let decoded = try BGJSON.decoder().decode(BGStatus.self, from: BGJSON.encoder().encode(s))
        #expect(decoded.voltage == 12000 && decoded.amperage == -1200)
        #expect(decoded.measurements == old)
    }

    @Test func decodingRejectsWrongUnitUnknownVersionAndDuplicateMetric() throws {
        let v = BGMeasurement(.batteryVoltage, value: 12, source: .registryPower, sampledAt: now)
        let bytes = try BGJSON.encoder().encode(BGBatteryMeasurements(values: [v]))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(throws: (any Error).self) {
            try BGJSON.decoder().decode(BGBatteryMeasurements.self, from: Data(text.replacingOccurrences(of: "\"V\"", with: "\"mV\"").utf8))
        }
        #expect(throws: (any Error).self) {
            try BGJSON.decoder().decode(BGBatteryMeasurements.self, from: Data(text.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2").utf8))
        }
        #expect(throws: (any Error).self) {
            try BGJSON.decoder().decode(BGBatteryMeasurements.self, from: BGJSON.encoder().encode(BGBatteryMeasurements(values: [v, v])))
        }
    }
}
