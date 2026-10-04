import Testing
import Foundation
@testable import BatteryGuardShared

@Suite("PowerFlow Tests")
struct PowerFlowTests {
    @Test("0 battery 12 input -> 12 system")
    func zeroBattery12Input() {
        let sample = BGPowerFlowSample(inputWatts: 12.0, batteryWatts: 0.0)
        #expect(sample.systemWatts == 12.0)
    }

    @Test("charging 20 input 5 battery -> 15")
    func charging20Input5Battery() {
        let sample = BGPowerFlowSample(inputWatts: 20.0, batteryWatts: 5.0)
        #expect(sample.systemWatts == 15.0)
    }

    @Test("discharge input 0 battery -10 -> 10")
    func dischargeInput0BatteryNegative10() {
        let sample = BGPowerFlowSample(inputWatts: 0.0, batteryWatts: -10.0)
        #expect(sample.systemWatts == 10.0)
    }

    @Test("weak input 5 battery -7 -> 12")
    func weakInput5BatteryNegative7() {
        let sample = BGPowerFlowSample(inputWatts: 5.0, batteryWatts: -7.0)
        #expect(sample.systemWatts == 12.0)
    }

    @Test("missing input nil -> nil despite 65 rating")
    func missingInputNilDespite65Rating() {
        let sample = BGPowerFlowSample(
            inputWatts: nil,
            batteryWatts: 5.0,
            adapterRatedWatts: 65.0
        )
        #expect(sample.systemWatts == nil)

        let sampleMissingBattery = BGPowerFlowSample(
            inputWatts: 12.0,
            batteryWatts: nil,
            adapterRatedWatts: 65.0
        )
        #expect(sampleMissingBattery.systemWatts == nil)
    }

    @Test("inconsistent negative balance -> nil")
    func inconsistentNegativeBalance() {
        let sample = BGPowerFlowSample(inputWatts: 5.0, batteryWatts: 10.0)
        #expect(sample.systemWatts == nil)

        let sampleZeroInput = BGPowerFlowSample(inputWatts: 0.0, batteryWatts: 5.0)
        #expect(sampleZeroInput.systemWatts == nil)
    }

    @Test("nan/inf missing and boundary validation")
    func nanInfMissing() {
        let sampleNaN = BGPowerFlowSample(
            inputWatts: .nan,
            batteryWatts: .nan,
            adapterRatedWatts: .nan,
            hardwarePercent: .nan
        )
        #expect(sampleNaN.inputWatts == nil)
        #expect(sampleNaN.batteryWatts == nil)
        #expect(sampleNaN.adapterRatedWatts == nil)
        #expect(sampleNaN.hardwarePercent == nil)
        #expect(sampleNaN.systemWatts == nil)

        let sampleInf = BGPowerFlowSample(
            inputWatts: .infinity,
            batteryWatts: -.infinity,
            adapterRatedWatts: .infinity,
            hardwarePercent: .infinity
        )
        #expect(sampleInf.inputWatts == nil)
        #expect(sampleInf.batteryWatts == nil)
        #expect(sampleInf.adapterRatedWatts == nil)
        #expect(sampleInf.hardwarePercent == nil)

        let sampleInvalid = BGPowerFlowSample(
            inputWatts: -1.0,
            batteryWatts: -5.0,
            adapterRatedWatts: 0.0,
            hardwarePercent: 105.0
        )
        #expect(sampleInvalid.inputWatts == nil)
        #expect(sampleInvalid.batteryWatts == -5.0)
        #expect(sampleInvalid.adapterRatedWatts == nil)
        #expect(sampleInvalid.hardwarePercent == nil)

        let sampleNegativePercent = BGPowerFlowSample(
            hardwarePercent: -0.1
        )
        #expect(sampleNegativePercent.hardwarePercent == nil)

        let sampleValidBoundaries = BGPowerFlowSample(
            inputWatts: 0.0,
            batteryWatts: 0.0,
            adapterRatedWatts: 0.001,
            hardwarePercent: 0.0
        )
        #expect(sampleValidBoundaries.inputWatts == 0.0)
        #expect(sampleValidBoundaries.batteryWatts == 0.0)
        #expect(sampleValidBoundaries.adapterRatedWatts == 0.001)
        #expect(sampleValidBoundaries.hardwarePercent == 0.0)

        let sample100Percent = BGPowerFlowSample(
            hardwarePercent: 100.0
        )
        #expect(sample100Percent.hardwarePercent == 100.0)
    }

    @Test("timestamp fresh/stale/future")
    func timestampFreshStaleFuture() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)

        let exactSample = BGPowerFlowSample(sampledAt: referenceDate)
        #expect(exactSample.isFresh(at: referenceDate))

        let freshPastSample = BGPowerFlowSample(sampledAt: referenceDate.addingTimeInterval(-5.0))
        #expect(freshPastSample.isFresh(at: referenceDate))

        let boundaryPastSample = BGPowerFlowSample(sampledAt: referenceDate.addingTimeInterval(-10.0))
        #expect(boundaryPastSample.isFresh(at: referenceDate))

        let staleSample = BGPowerFlowSample(sampledAt: referenceDate.addingTimeInterval(-10.1))
        #expect(!staleSample.isFresh(at: referenceDate))

        let freshFutureSample = BGPowerFlowSample(sampledAt: referenceDate.addingTimeInterval(3.0))
        #expect(freshFutureSample.isFresh(at: referenceDate))

        let boundaryFutureSample = BGPowerFlowSample(sampledAt: referenceDate.addingTimeInterval(5.0))
        #expect(boundaryFutureSample.isFresh(at: referenceDate))

        let tooFarFutureSample = BGPowerFlowSample(sampledAt: referenceDate.addingTimeInterval(5.1))
        #expect(!tooFarFutureSample.isFresh(at: referenceDate))
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = BGPowerFlowSample(
            sampledAt: date,
            inputWatts: 45.0,
            batteryWatts: -15.0,
            adapterRatedWatts: 67.0,
            hardwarePercent: 85.0,
            source: "AppleSmartBattery"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BGPowerFlowSample.self, from: data)

        #expect(decoded == original)
        #expect(decoded.systemWatts == 60.0)
        #expect(decoded.isFresh(at: date))
    }
}
