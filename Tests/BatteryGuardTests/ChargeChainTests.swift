import Testing
import Foundation
import BatteryGuardShared

struct ChargeChainTests {
    nonisolated(unsafe) static let props: [String: Any] = [
        "AdapterDetails": [
            "Name": "96W USB-C Power Adapter", "Manufacturer": "Apple Inc.", "Watts": 60,
            "UsbHvcMenu": [
                ["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 3000],
                ["Index": 3, "MaxVoltage": 20000, "MaxCurrent": 4700],
            ],
        ] as [String: Any],
    ]

    func status(plugged: Bool = true, state: BGChargeState = .holding) -> BGStatus {
        var s = BGStatus(); s.pluggedIn = plugged; s.state = state; return s
    }

    @Test func parsesNegotiatedAndOfferedWatts() throws {
        let adapter = try #require(BGAdapterDetails(properties: Self.props))
        #expect(adapter.negotiatedWatts == 60)
        #expect(adapter.offeredMaxWatts == 94)
        #expect(adapter.name == "96W USB-C Power Adapter")
        #expect(adapter.identity == "Apple Inc.|96W USB-C Power Adapter|94")
        #expect(BGAdapterDetails(properties: [:]) == nil)
    }

    @Test func cableLimitIsDetectedWhenAdapterOffersMore() {
        let adapter = BGAdapterDetails(properties: Self.props)
        #expect(BGChargeChainCheck.evaluate(adapter: adapter, status: status(), batteryWatts: 0, bestKnownWatts: nil)
                == [.cableOrDockLimit(negotiated: 60, offered: 94)])
    }

    @Test func weakAdapterAndDrainAreReported() {
        let adapter = BGAdapterDetails(name: "Generic", negotiatedWatts: 20, offeredMaxWatts: 20)
        let findings = BGChargeChainCheck.evaluate(adapter: adapter, status: status(state: .charging),
                                                   batteryWatts: -5, bestKnownWatts: nil)
        #expect(findings == [.weakAdapter(watts: 20), .drainingWhilePlugged(watts: -5)])
    }

    @Test func intentionalDischargeIsNotADrainFinding() {
        let adapter = BGAdapterDetails(name: "Apple", negotiatedWatts: 96, offeredMaxWatts: 96)
        #expect(BGChargeChainCheck.evaluate(adapter: adapter, status: status(state: .discharging),
                                            batteryWatts: -10, bestKnownWatts: nil) == [.ok(negotiated: 96)])
    }

    @Test func lowerThanBeforeUsesAdapterMemory() {
        var memory = BGAdapterMemory()
        let good = BGAdapterDetails(name: "Dock", negotiatedWatts: 60, offeredMaxWatts: nil)
        memory = memory.observing(good)
        let poor = BGAdapterDetails(name: "Dock", negotiatedWatts: 30, offeredMaxWatts: nil)
        #expect(memory.observing(poor) == memory)
        #expect(BGChargeChainCheck.evaluate(adapter: poor, status: status(), batteryWatts: 0,
                                            bestKnownWatts: memory.best(for: poor))
                == [.lowerThanBefore(negotiated: 30, best: 60)])
    }

    @Test func unpluggedOnlyReportsFlapping() {
        var s = status(plugged: false, state: .onBattery)
        #expect(BGChargeChainCheck.evaluate(adapter: nil, status: s, batteryWatts: -8, bestKnownWatts: nil).isEmpty)
        s.adapterReconnectsLastHour = 5
        #expect(BGChargeChainCheck.evaluate(adapter: nil, status: s, batteryWatts: -8, bestKnownWatts: nil)
                == [.flapping(count: 5)])
    }
}
