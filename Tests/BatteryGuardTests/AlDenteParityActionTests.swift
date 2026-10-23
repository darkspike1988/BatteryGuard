import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct AlDenteParityActionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func setLimitKeepsTheBandAndLeavesMacOSMode() throws {
        var c = BGConfig(); c.lowerLimit = 70; c.upperLimit = 80; c.mode = .native
        let next = try BGChargingActionRequest(action: .setLimit, targetPercent: 60).applying(to: c, at: now)
        #expect(next.upperLimit == 60 && next.lowerLimit == 50)
        #expect(next.mode == .auto)
        #expect(next.manualOverrideUntil == now.addingTimeInterval(2 * 3600))
        #expect(throws: BGChargingActionError.self) {
            try BGChargingActionRequest(action: .setLimit, targetPercent: 10).applying(to: c, at: now)
        }
    }

    @Test func lowPowerAndLEDActionsDoNotOverrideSchedules() throws {
        let c = BGConfig()
        let lpm = try BGChargingActionRequest(action: .lowPowerMode, enabled: true).applying(to: c, at: now)
        #expect(lpm.lowPowerModeOnBattery && lpm.manualOverrideUntil == nil)
        let led = try BGChargingActionRequest(action: .magsafeLED, enabled: false).applying(to: c, at: now)
        #expect(!led.magsafeLed && led.manualOverrideUntil == nil)
    }

    @Test func newActionsDecodeOnlyTheirFields() throws {
        let ok = #"{"action":"set-limit","targetPercent":75}"#
        #expect(try BGJSON.decoder().decode(BGChargingActionRequest.self, from: Data(ok.utf8)).targetPercent == 75)
        let wrong = #"{"action":"low-power-mode","targetPercent":75}"#
        #expect(throws: (any Error).self) {
            try BGJSON.decoder().decode(BGChargingActionRequest.self, from: Data(wrong.utf8))
        }
    }

    @Test func limitAndPauseSchedulesValidateAndMapToActions() throws {
        let limit = BGScheduledAction(kind: .limit, targetPercent: 90)
        #expect(try limit.request() == BGChargingActionRequest(action: .setLimit, targetPercent: 90))
        let pause = BGScheduledAction(kind: .pause, minutes: 120)
        #expect(try pause.request() == BGChargingActionRequest(action: .pause, minutes: 120))
        #expect(throws: BGChargingActionError.self) { try BGScheduledAction(kind: .limit, minutes: 5, targetPercent: 90).validate() }
        #expect(throws: BGChargingActionError.self) { try BGScheduledAction(kind: .pause).validate() }
        #expect(throws: BGChargingActionError.self) { try BGScheduledAction(kind: .pause, minutes: 900).validate() }
    }

    @Test func limitScheduleRunsWithoutChargeControl() throws {
        var c = BGConfig()
        let rule = try ScheduledRule(id: UUID(), name: "Abends", timeZoneIdentifier: "UTC",
                                     startsAt: now, recurrence: .daily)
        c.scheduledTasks = [BGScheduledTask(schedule: rule, enabled: true, catchUp: false,
                                            action: BGScheduledAction(kind: .limit, targetPercent: 100), state: .init())]
        let context = BGSpecialPlanEvaluationContext(percent: 50, externalPower: .connected, canBlockCharging: false,
                                                     canDisconnectAdapter: false, allowsAdapterDisconnect: true)
        let next = ScheduleRunner.evaluate(config: c, now: now.addingTimeInterval(5), context: context)
        #expect(next.upperLimit == 100)
        #expect(next.scheduledTasks.first?.state.lastResult == "stored: requested action")
    }
}
