import Foundation

/// Clear only the request evaluated by a completed controller tick. New requests
/// can be saved by the IPC queue while that tick is reading hardware.
public enum BGChargeCompletion {
    public static func applying(snapshot: BGConfig, to latest: BGConfig, at now: Date) -> BGConfig {
        var result = latest
        if snapshot.chargeToFullOnce, latest.chargeToFullOnce,
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
}
