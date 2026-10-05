import Foundation

/// Clear only the request evaluated by a completed controller tick. New requests
/// can be saved by the IPC queue while that tick is reading hardware.
public enum BGChargeCompletion {
    public static func applying(snapshot: BGConfig, to latest: BGConfig, at now: Date) -> BGConfig {
        var result = latest
        if snapshot.specialChargePlan?.kind != .topUp, snapshot.chargeToFullOnce, latest.chargeToFullOnce,
           latest.fullChargeUntil == snapshot.fullChargeUntil,
           latest.fullChargeRequestID == snapshot.fullChargeRequestID {
            result.chargeToFullOnce = false
            result.fullChargeUntil = nil
            result.fullChargeRequestID = nil
        }
        if snapshot.isTravelCharging(at: now),
           latest.travelReadyAt == snapshot.travelReadyAt,
           latest.travelRequestID == snapshot.travelRequestID {
            result.travelReadyAt = nil
            result.travelRequestID = nil
        }
        return result
    }

    /// Compare-and-clear helper for special charge plans to protect against races.
    /// Clears the special plan only if the latest config still has the exact same requestID.
    public static func special(snapshot: BGConfig, toLatest latest: BGConfig) -> BGConfig {
        var result = latest
        if let snapshotPlan = snapshot.specialChargePlan,
           let latestPlan = latest.specialChargePlan,
           latestPlan.requestID == snapshotPlan.requestID {
            result.specialChargePlan = nil
        }
        return result
    }

    public static func applyingSpecial(snapshot: BGConfig, to latest: BGConfig) -> BGConfig {
        special(snapshot: snapshot, toLatest: latest)
    }
}
