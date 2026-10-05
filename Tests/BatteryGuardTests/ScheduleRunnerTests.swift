import Foundation
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct ScheduleRunnerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var context: BGSpecialPlanEvaluationContext {
        BGSpecialPlanEvaluationContext(percent: 70, externalPower: .connected,
            canBlockCharging: true, canDisconnectAdapter: true, allowsAdapterDisconnect: true)
    }
    func task(_ action: BGScheduledAction = BGScheduledAction(kind: .topUp), age: Double = 0,
              catchUp: Bool = false, id: UUID = UUID(), recurrence: ScheduledRule.Recurrence = .once) throws -> BGScheduledTask {
        BGScheduledTask(schedule: try ScheduledRule(id: id, name: "Test", timeZoneIdentifier: "UTC",
            startsAt: now.addingTimeInterval(-age), recurrence: recurrence), enabled: true, catchUp: catchUp, action: action)
    }
    func run(_ c: BGConfig, at date: Date? = nil, using custom: BGSpecialPlanEvaluationContext? = nil) -> BGConfig {
        ScheduleRunner.evaluate(config: c, now: date ?? now, context: custom ?? context)
    }
    @Test func exactlyOnceAcrossRestart() throws {
        var c = BGConfig(); c.scheduledTasks = [try task()]
        let first = run(c)
        #expect(first.specialChargePlan != nil)
        #expect(first.scheduleHistory.count == 1)
        #expect(!ScheduleRunner.needsEvaluation(config: first, now: now))
        #expect(run(first) == first)
        let restarted = try BGJSON.decoder().decode(BGConfig.self, from: BGJSON.encoder().encode(first))
        #expect(run(restarted).scheduleHistory.count == 1)
    }
    @Test func manualOverrideSkipsWithoutLaterBacklog() throws {
        var c = BGConfig(); c.scheduledTasks = [try task(catchUp: true)]
        c.manualOverrideUntil = now.addingTimeInterval(60)
        let skipped = run(c)
        #expect(skipped.specialChargePlan == nil)
        #expect(skipped.scheduleHistory.first?.resultString == "skipped: manual override")
        #expect(run(skipped, at: now.addingTimeInterval(120)).scheduleHistory.count == 1)
    }
    @Test func newestOnlyAndDeterministicTie() throws {
        var c = BGConfig()
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        c.scheduledTasks = [try task(age: 10, catchUp: true), try task(id: high), try task(id: low)]
        let result = run(c)
        #expect(result.scheduleHistory.filter { $0.resultString == "stored: requested action" }.count == 1)
        #expect(result.scheduleHistory.first?.taskID == low)
        #expect(result.scheduleHistory.count == 3)
    }
    @Test func missedAndFailedOccurrencesDoNotRetry() throws {
        var c = BGConfig(); c.scheduledTasks = [try task(age: 31)]
        #expect(run(c).scheduleHistory.first?.resultString == "skipped: missed occurrence")
        c.scheduledTasks = [try task()]
        var unavailable = context; unavailable.canBlockCharging = false
        let failed = run(c, using: unavailable)
        #expect(failed.specialChargePlan == nil)
        #expect(failed.scheduleHistory.first?.resultString.hasPrefix("failed:") == true)
        #expect(run(failed).scheduleHistory.count == 1)
        c.scheduledTasks = [try task(BGScheduledAction(kind: .hold))]
        #expect(run(c).specialChargePlan == nil)
    }
    @Test func profileSnapshotAndHistoryBound() throws {
        let snapshot = try BGSavedProfile(name: "Stored", lowerLimit: 40, upperLimit: 50)
        var c = BGConfig(); c.scheduledTasks = [try task(BGScheduledAction(kind: .profile, profile: snapshot))]
        c.manualOverrideUntil = now.addingTimeInterval(-60)
        c.scheduleHistory = (0..<100).map { _ in BGScheduleRun(taskID: UUID(), occurrenceAt: now, executedAt: now, resultString: "stored") }
        var unavailable = context; unavailable.canBlockCharging = false
        let changed = run(c, using: unavailable)
        #expect(changed.upperLimit == 50 && changed.lowerLimit == 40)
        #expect(changed.manualOverrideUntil == c.manualOverrideUntil)
        #expect(changed.scheduleHistory.count == 100)
    }
    @Test func clockCorrectionResetsFutureWatermark() throws {
        var c = BGConfig(); c.scheduledTasks = [try task(recurrence: .daily)]
        c.scheduledTasks[0].state = BGScheduleExecutionState(lastOccurrenceDate: now.addingTimeInterval(86400 * 30), lastExecutionDate: now.addingTimeInterval(86400 * 30))
        c.manualOverrideUntil = now.addingTimeInterval(86400 * 31)
        let corrected = run(c)
        #expect(corrected.manualOverrideUntil == nil)
        #expect(corrected.scheduleHistory.first?.resultString == "skipped: clock correction")
        #expect(corrected.specialChargePlan == nil)
        #expect(run(corrected, at: now.addingTimeInterval(86400)).specialChargePlan != nil)
    }
    @Test func activeManualRequestsSuppressEveryTask() throws {
        let scheduled = try task(catchUp: true)
        var paused = BGConfig(); paused.pauseUntil = now.addingTimeInterval(60)
        var full = BGConfig(); full.chargeToFullOnce = true; full.fullChargeUntil = now.addingTimeInterval(60)
        var travel = BGConfig(); travel.travelReadyAt = now.addingTimeInterval(60)
        var special = BGConfig()
        special.specialChargePlan = BGSpecialChargePlan(kind: .topUp, targetPercent: 100,
            createdAt: now, expiresAt: now.addingTimeInterval(60))
        for var original in [paused, full, travel, special] {
            original.scheduledTasks = [scheduled]
            let result = run(original)
            #expect(result.scheduleHistory.first?.resultString == "skipped: manual override")
            #expect(result.specialChargePlan == original.specialChargePlan)
        }
    }
    @Test func strictActionAndStateDecode() throws {
        #expect(throws: BGChargingActionError.self) {
            try BGScheduledAction(kind: .profile, minutes: 5).validate()
        }
        #expect(throws: BGChargingActionError.self) {
            try BGScheduledAction(kind: .hold, targetPercent: 50).validate()
        }
        var invalid = try task()
        invalid.state = BGScheduleExecutionState(lastExecutionDate: Date(timeIntervalSince1970: .infinity))
        #expect(throws: (any Error).self) { try invalid.validated() }
        let data = Data("{\"kind\":\"topUp\",\"secret\":\"value\"}".utf8)
        #expect(throws: (any Error).self) { try BGJSON.decoder().decode(BGScheduledAction.self, from: data) }
    }
}
