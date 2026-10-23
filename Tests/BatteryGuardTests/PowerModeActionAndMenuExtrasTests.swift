import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct PowerModeActionAndMenuExtrasTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func powerModeActionChangesOnlyGivenRulesWithoutManualOverride() throws {
        let request = try BGJSON.decoder().decode(BGChargingActionRequest.self,
            from: Data(#"{"action":"power-mode","lowPowerMode":"onBattery"}"#.utf8))
        var config = BGConfig()
        config.highPowerModeRule = .onAdapter
        let next = try request.applying(to: config, at: now)
        #expect(next.lowPowerModeRule == .onBattery && next.lowPowerModeOnBattery)
        #expect(next.highPowerModeRule == .onAdapter)
        #expect(next.manualOverrideUntil == nil)
    }

    @Test func powerModeActionRejectsEmptyUnknownAndForeignFields() {
        let decoder = BGJSON.decoder()
        #expect(throws: (any Error).self) {
            try decoder.decode(BGChargingActionRequest.self, from: Data(#"{"action":"power-mode"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try decoder.decode(BGChargingActionRequest.self, from: Data(#"{"action":"power-mode","lowPowerMode":"turbo"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try decoder.decode(BGChargingActionRequest.self, from: Data(#"{"action":"power-mode","lowPowerMode":"always","minutes":5}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try decoder.decode(BGChargingActionRequest.self, from: Data(#"{"action":"pause","minutes":5,"lowPowerMode":"always"}"#.utf8))
        }
    }

    @Test func menuExtrasKeepCatalogOrderAndIgnoreUnknownEntries() {
        #expect(MenuBarExtraItem.decode("socPower,bogus,timeRemaining") == [.timeRemaining, .socPower])
        let toggled = MenuBarExtraItem.toggled(.chargeLimit, in: "socPower")
        #expect(toggled == "chargeLimit,socPower")
        #expect(MenuBarExtraItem.toggled(.socPower, in: toggled) == "chargeLimit")
    }

    @Test func menuExtrasShowOnlyCurrentValues() {
        var status = BGStatus()
        status.timeRemainingMinutes = 83
        status.effectiveUpperLimit = 80
        status.socPower = BGSoCPower(sampledAt: now, cpuWatts: 1.25, gpuWatts: 0.1, aneWatts: 0)
        let items = MenuBarExtraItem.allCases
        #expect(MenuBarExtraFormatter.texts(for: items, status: status, isDaemonActive: true, now: now)
                == ["1:23 h", "→80 %", "SoC 1.4 W"])
        #expect(MenuBarExtraFormatter.texts(for: items, status: status, isDaemonActive: false, now: now).isEmpty)
        #expect(MenuBarExtraFormatter.texts(for: [.socPower], status: status, isDaemonActive: true,
                                            now: now.addingTimeInterval(600)).isEmpty)
        status.timeRemainingMinutes = 0
        #expect(MenuBarExtraFormatter.texts(for: [.timeRemaining], status: status, isDaemonActive: true, now: now).isEmpty)
        #expect(MenuBarExtraFormatter.showsLowPowerSymbol(for: [.lowPowerMode], lowPowerModeEnabled: true))
        #expect(!MenuBarExtraFormatter.showsLowPowerSymbol(for: [], lowPowerModeEnabled: true))
    }
}
