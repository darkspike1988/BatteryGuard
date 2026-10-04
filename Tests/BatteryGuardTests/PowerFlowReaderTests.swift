import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct PowerFlowReaderTests {
    private let date = Date(timeIntervalSince1970: 1_000_000)

    private func parse(_ properties: [String: Any]) -> BGPowerFlowSample {
        PowerFlowReader.parse(properties: properties, sampledAt: date)
    }

    private func close(_ lhs: Double?, _ rhs: Double) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) < 1e-9
    }

    @Test func zeroPower() {
        let sample = parse([
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 0],
            "Voltage": 12000,
            "InstantAmperage": 0,
        ])
        #expect(sample.inputWatts == 0)
        #expect(sample.batteryWatts == 0)
        #expect(sample.sampledAt == date)
        #expect(sample.source == "AppleSmartBattery/PowerTelemetryData")
    }

    @Test func charging() {
        let sample = parse([
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 30000],
            "AdapterDetails": ["Watts": 65],
            "Voltage": 12000,
            "InstantAmperage": 2000,
            "AppleRawCurrentCapacity": 2500,
            "AppleRawMaxCapacity": 5000,
        ])
        #expect(close(sample.inputWatts, 30))
        #expect(close(sample.batteryWatts, 24))
        #expect(sample.adapterRatedWatts == 65)
        #expect(close(sample.hardwarePercent, 50))
    }

    @Test func discharging() {
        let sample = parse([
            "ExternalConnected": false,
            "Voltage": 11000,
            "InstantAmperage": -1500,
        ])
        #expect(sample.inputWatts == 0)
        #expect(close(sample.batteryWatts, -16.5))
        #expect(sample.adapterRatedWatts == nil)
    }

    @Test func weakAdapter() {
        let sample = parse([
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 5000],
            "AdapterDetails": ["Watts": 65],
            "Voltage": 11000,
            "InstantAmperage": -1000,
        ])
        #expect(close(sample.inputWatts, 5))
        #expect(sample.adapterRatedWatts == 65)
        #expect(close(sample.batteryWatts, -11))
    }

    @Test func missingInputDespiteAdapterRating() {
        let sample = parse([
            "ExternalConnected": true,
            "AdapterDetails": ["Watts": 65],
            "Voltage": 12000,
            "InstantAmperage": 100,
        ])
        #expect(sample.inputWatts == nil)
        #expect(sample.adapterRatedWatts == 65)
    }

    @Test func unpluggedIgnoresStaleInput() {
        let sample = parse([
            "ExternalConnected": false,
            "PowerTelemetryData": ["SystemPowerIn": 20000],
            "AdapterDetails": ["Watts": 96],
        ])
        #expect(sample.inputWatts == 0)
        #expect(sample.adapterRatedWatts == nil)
    }

    @Test func missingExternalConnected() {
        let sample = parse([
            "PowerTelemetryData": ["SystemPowerIn": 20000],
            "AdapterDetails": ["Watts": 96],
        ])
        #expect(sample.inputWatts == nil)
        #expect(sample.adapterRatedWatts == nil)
    }

    @Test func outOfRangeInputRejected() {
        let high = parse([
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 1_000_001],
        ])
        let negative = parse([
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": -1],
        ])
        #expect(high.inputWatts == nil)
        #expect(negative.inputWatts == nil)
    }

    @Test func booleanValuesRejected() {
        let sample = parse([
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": true],
            "AdapterDetails": ["Watts": true],
            "Voltage": true,
            "InstantAmperage": 1000,
            "AppleRawCurrentCapacity": true,
            "AppleRawMaxCapacity": 5000,
        ])
        #expect(sample.inputWatts == nil)
        #expect(sample.adapterRatedWatts == nil)
        #expect(sample.batteryWatts == nil)
        #expect(sample.hardwarePercent == nil)

        let booleanCurrent = parse([
            "Voltage": 12000,
            "InstantAmperage": true,
            "Amperage": 1000,
        ])
        #expect(booleanCurrent.batteryWatts == nil)
    }

    @Test func unsignedNegativeCurrentDecoded() {
        let u64 = parse([
            "Voltage": 12000,
            "InstantAmperage": UInt64(bitPattern: -1500),
        ])
        let u32 = parse([
            "Voltage": 12000,
            "InstantAmperage": UInt32(bitPattern: -1500),
        ])
        #expect(close(u64.batteryWatts, -18))
        #expect(close(u32.batteryWatts, -18))
    }

    @Test func amperageFallbackOnlyWhenInstantAbsent() {
        let fallback = parse(["Voltage": 10000, "Amperage": 1000])
        #expect(close(fallback.batteryWatts, 10))
        let preferred = parse(["Voltage": 10000, "InstantAmperage": 2000, "Amperage": 1000])
        #expect(close(preferred.batteryWatts, 20))
    }

    @Test func outOfRangeVoltageAndCurrentRejected() {
        #expect(parse(["Voltage": 0, "InstantAmperage": 100]).batteryWatts == nil)
        #expect(parse(["Voltage": 50001, "InstantAmperage": 100]).batteryWatts == nil)
        #expect(parse(["Voltage": 12000, "InstantAmperage": 30001]).batteryWatts == nil)
        #expect(parse(["Voltage": 12000, "InstantAmperage": -30001]).batteryWatts == nil)
        #expect(parse(["Voltage": "12000", "InstantAmperage": 100]).batteryWatts == nil)
        #expect(parse(["Voltage": Double.nan, "InstantAmperage": 100]).batteryWatts == nil)
    }

    @Test func adapterWattsBounds() {
        func adapter(_ watts: Any) -> Double? {
            parse(["ExternalConnected": true, "AdapterDetails": ["Watts": watts]]).adapterRatedWatts
        }
        #expect(adapter(0) == nil)
        #expect(adapter(-5) == nil)
        #expect(adapter(1001) == nil)
        #expect(adapter(1000) == 1000)
    }

    @Test func hardwarePercentValidation() {
        #expect(parse(["AppleRawCurrentCapacity": 0, "AppleRawMaxCapacity": 100]).hardwarePercent == 0)
        #expect(parse(["AppleRawCurrentCapacity": 100, "AppleRawMaxCapacity": 0]).hardwarePercent == nil)
        #expect(parse(["AppleRawCurrentCapacity": -1, "AppleRawMaxCapacity": 100]).hardwarePercent == nil)
        #expect(parse(["AppleRawCurrentCapacity": 101, "AppleRawMaxCapacity": 100]).hardwarePercent == nil)
        #expect(parse(["AppleRawCurrentCapacity": 50]).hardwarePercent == nil)
    }
}
