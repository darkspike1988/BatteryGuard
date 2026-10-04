import Foundation

public struct LowBatteryWarningPolicy: Sendable, Equatable {
    public static let defaultThreshold: Int = 20
    public static let minThreshold: Int = 5
    public static let maxThreshold: Int = 50
    public static let validRange: ClosedRange<Int> = minThreshold...maxThreshold
    public static let hysteresis: Int = 2
    public static let userDefaultsKey: String = "bg.lowBatteryThreshold"

    public var didWarn: Bool

    public init(didWarn: Bool = false) {
        self.didWarn = didWarn
    }

    public static func clampThreshold(_ value: Int) -> Int {
        min(max(value, minThreshold), maxThreshold)
    }

    public static func threshold(from userDefaults: UserDefaults = .standard) -> Int {
        guard let raw = userDefaults.object(forKey: userDefaultsKey) as? Int else {
            return defaultThreshold
        }
        return clampThreshold(raw)
    }

    @discardableResult
    public mutating func evaluate(
        percent: Int,
        onBattery: Bool,
        threshold: Int = defaultThreshold,
        enabled: Bool = true
    ) -> Bool {
        let effectiveThreshold = Self.clampThreshold(threshold)

        guard onBattery else {
            didWarn = false
            return false
        }

        if percent <= effectiveThreshold {
            if !didWarn && enabled {
                didWarn = true
                return true
            }
        } else if percent > effectiveThreshold + Self.hysteresis {
            didWarn = false
        }

        return false
    }

}
