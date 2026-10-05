import Foundation
import BatteryGuardShared

/// Pure scheduler. Execution and skipped occurrences are committed with configuration atomically.
public enum ScheduleRunner {
    private static func clockCorrection(task: BGScheduledTask, now: Date) -> Bool {
        [task.state.lastExecutionDate, task.state.lastOccurrenceDate].compactMap { $0 }
            .contains { $0.timeIntervalSince(now) > 24 * 3600 }
    }

    public static func needsEvaluation(config: BGConfig, now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite else { return false }
        return config.scheduledTasks.contains { task in
            guard task.enabled, let occurrence = task.schedule.mostRecentOccurrence(at: now) else { return false }
            if clockCorrection(task: task, now: now) { return true }
            if let execution = task.state.lastExecutionDate, now < execution { return false }
            return task.state.lastOccurrenceDate.map { occurrence > $0 } ?? true
        }
    }

    public static func evaluate(config: BGConfig, now: Date,
                                context: BGSpecialPlanEvaluationContext,
                                specialHardwareVerified: Bool = false) -> BGConfig {
        guard needsEvaluation(config: config, now: now) else { return config }
        var next = config
        let overrideClockCorrection = config.manualOverrideUntil.map { $0.timeIntervalSince(now) > 24 * 3600 } ?? false
        let overridden = (config.calibrationPlan.map { $0.expiresAt > now } ?? false)
            || config.isPaused(at: now)
            || (config.chargeToFullOnce && (config.fullChargeUntil.map { $0 > now } ?? true))
            || config.isTravelCharging(at: now)
            || (config.specialChargePlan.map { $0.expiresAt > now } ?? false)
            || (config.manualOverrideUntil.map { $0 > now } ?? false)
        let candidates = config.scheduledTasks.enumerated().compactMap { index, task -> (Int, Date)? in
            guard task.enabled, let occurrence = task.schedule.mostRecentOccurrence(at: now),
                  (clockCorrection(task: task, now: now) || (task.state.lastOccurrenceDate.map({ occurrence > $0 }) ?? true)),
                  (clockCorrection(task: task, now: now) || (task.state.lastExecutionDate.map({ now >= $0 }) ?? true)) else { return nil }
            return (index, occurrence)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return config.scheduledTasks[lhs.0].id.uuidString < config.scheduledTasks[rhs.0].id.uuidString
        }
        var selected = false
        for (index, occurrence) in candidates {
            let task = config.scheduledTasks[index]
            let pending = task.schedule.pendingOccurrence(at: now, state: task.state,
                catchUp: task.catchUp, manualOverrideUntil: config.manualOverrideUntil)
            let result: String
            if clockCorrection(task: task, now: now) || overrideClockCorrection {
                result = "skipped: clock correction"
            } else if overridden || pending == nil {
                result = overridden ? "skipped: manual override" : "skipped: missed occurrence"
            } else if selected {
                result = "skipped: newer task selected"
            } else {
                selected = true
                do {
                    var request = try task.action.request()
                    if task.action.kind != .profile {
                        guard context.canBlockCharging, let percent = context.percent, (0...100).contains(percent) else {
                            throw BGChargingActionError.invalidRequest("Unavailable charge control")
                        }
                        if task.action.kind == .hold {
                            guard specialHardwareVerified else { throw BGChargingActionError.invalidRequest("Unverified hold backend") }
                            request.targetPercent = percent
                        }
                        if task.action.kind == .discharge {
                            guard specialHardwareVerified && context.canDisconnectAdapter && context.allowsAdapterDisconnect else {
                                throw BGChargingActionError.invalidRequest("Unavailable adapter control")
                            }
                        }
                    }
                    let manualOverride = next.manualOverrideUntil
                    next = try request.applying(to: next, at: now)
                    next.manualOverrideUntil = manualOverride
                    result = "stored: requested action"
                } catch {
                    // Stable bounded result codes contain no profile names or request details.
                    result = "failed: action unavailable or invalid"
                }
            }
            next.scheduledTasks[index].state = BGScheduleExecutionState(lastOccurrenceDate: occurrence,
                lastResult: result, lastExecutionDate: now)
            next.scheduleHistory.append(BGScheduleRun(taskID: task.id, occurrenceAt: occurrence,
                executedAt: now, resultString: result))
        }
        if overrideClockCorrection { next.manualOverrideUntil = nil }
        next.scheduleHistory = Array(next.scheduleHistory.suffix(100))
        return next
    }
}
