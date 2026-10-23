import Foundation

/// Auffällige Ladezustände, die B-Guard erklärt statt still zu übergehen.
public enum BGChargeAnomaly: Equatable, Sendable {
    /// Ladestand liegt am Netzteil deutlich über dem wirksamen Ziel.
    case overLimit(percent: Int, limit: Int)
    /// macOS lädt für die Akku-Kalibrierung („Gauging“) bewusst über das Limit.
    case appleCalibration
    /// Netzteil gemeldet, aber es kommt kaum Leistung an und der Akku versorgt den Mac.
    case externalPowerMissing

    /// Prozentpunkte über dem Ziel, ab denen „über das Limit geladen“ gilt (Firmware-Hysterese berücksichtigt).
    public static let overLimitMargin = 3

    public static func evaluate(status: BGStatus, config: BGConfig, inputWatts: Double?, batteryWatts: Double?,
                                now: Date = Date()) -> [BGChargeAnomaly] {
        guard status.hasBatteryPercent, status.hasExternalPower, status.pluggedIn else { return [] }
        var result: [BGChargeAnomaly] = []
        let effective = config.effective(at: now)
        let controlling = config.enabled && !config.isPaused(at: now) && config.mode != .native && config.mode != .direct
        let fullChargeRequested = effective.chargeToFullOnce || effective.specialChargePlan?.kind == .topUp
        if status.appleCalibrationActive == true {
            result.append(.appleCalibration)
        } else if controlling, !fullChargeRequested, let limit = status.effectiveUpperLimit,
                  limit < 100, status.percent >= limit + overLimitMargin {
            result.append(.overLimit(percent: status.percent, limit: limit))
        }
        // Firmware-Entladung über dem Limit sieht genauso aus; nur unterhalb des Ziels melden.
        let belowTarget = status.effectiveUpperLimit.map { status.percent < $0 } ?? true
        if status.state != .discharging, belowTarget, let input = inputWatts, input < 1,
           let battery = batteryWatts, battery < -1 {
            result.append(.externalPowerMissing)
        }
        return result
    }
}
