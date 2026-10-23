import Foundation

/// Netzteilangaben aus `AdapterDetails` (AppleSmartBattery, nur lesend). „Watts“ ist die mit dem
/// Mac ausgehandelte Leistung; `UsbHvcMenu` listet, was das Netzteil per USB Power Delivery anbietet.
public struct BGAdapterDetails: Codable, Equatable, Sendable {
    public var name: String?
    public var manufacturer: String?
    public var negotiatedWatts: Int?
    /// Höchste vom Netzteil angebotene Stufe (Spannung × Strom), falls gemeldet.
    public var offeredMaxWatts: Int?

    public init(name: String? = nil, manufacturer: String? = nil, negotiatedWatts: Int? = nil,
                offeredMaxWatts: Int? = nil) {
        self.name = name
        self.manufacturer = manufacturer
        self.negotiatedWatts = negotiatedWatts
        self.offeredMaxWatts = offeredMaxWatts
    }

    public init?(properties: [String: Any]) {
        guard let details = properties["AdapterDetails"] as? [String: Any] else { return nil }
        name = (details["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (details["Description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        manufacturer = details["Manufacturer"] as? String
        negotiatedWatts = Self.number(details["Watts"]).flatMap { $0 > 0 && $0 <= 1000 ? Int($0.rounded()) : nil }
        let menu = details["UsbHvcMenu"] as? [[String: Any]] ?? []
        let offered = menu.compactMap { entry -> Double? in
            guard let volts = Self.number(entry["MaxVoltage"]), let amps = Self.number(entry["MaxCurrent"]),
                  volts > 0, amps > 0 else { return nil }
            return volts * amps / 1_000_000
        }.max()
        offeredMaxWatts = offered.flatMap { $0 <= 1000 ? Int($0.rounded()) : nil }
        if negotiatedWatts == nil && offeredMaxWatts == nil && name == nil { return nil }
    }

    /// Wiedererkennung desselben Netzteils über Sitzungen hinweg (ohne Seriennummer).
    public var identity: String? {
        guard let name else { return nil }
        return [manufacturer ?? "", name, offeredMaxWatts.map(String.init) ?? ""].joined(separator: "|")
    }

    private static func number(_ value: Any?) -> Double? {
        if let int = value as? Int { return Double(int) }
        if let double = value as? Double, double.isFinite { return double }
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? number.doubleValue : nil }
        return nil
    }
}

public enum BGChargeChainFinding: Equatable, Sendable {
    /// Netzteil bietet mehr an, als ausgehandelt wurde – typisch für ein 3-A-Kabel oder ein Dock.
    case cableOrDockLimit(negotiated: Int, offered: Int)
    /// Dasselbe Netzteil lieferte früher deutlich mehr.
    case lowerThanBefore(negotiated: Int, best: Int)
    case weakAdapter(watts: Int)
    case drainingWhilePlugged(watts: Double)
    case flapping(count: Int)
    case ok(negotiated: Int?)
}

public enum BGChargeChainCheck {
    public static let weakAdapterWatts = 30
    public static let cableLimitRatio = 0.75
    public static let drainWatts = -3.0
    public static let lowerThanBeforeRatio = 0.7

    public static func evaluate(adapter: BGAdapterDetails?, status: BGStatus, batteryWatts: Double?,
                                bestKnownWatts: Int?) -> [BGChargeChainFinding] {
        var findings: [BGChargeChainFinding] = []
        if let flaps = status.adapterReconnectsLastHour, flaps >= BGChargingExplanation.flappingThreshold {
            findings.append(.flapping(count: flaps))
        }
        guard status.pluggedIn else { return findings }
        let negotiated = adapter?.negotiatedWatts
        if let negotiated, let offered = adapter?.offeredMaxWatts, offered >= 65,
           Double(negotiated) <= Double(offered) * cableLimitRatio {
            findings.append(.cableOrDockLimit(negotiated: negotiated, offered: offered))
        } else if let negotiated, let best = bestKnownWatts,
                  Double(negotiated) < Double(best) * lowerThanBeforeRatio {
            findings.append(.lowerThanBefore(negotiated: negotiated, best: best))
        }
        if let negotiated, negotiated < weakAdapterWatts {
            findings.append(.weakAdapter(watts: negotiated))
        }
        // Gewolltes Entladen am Kabel (Sonderaktion) ist kein Mangel des Netzteils.
        if let batteryWatts, batteryWatts <= drainWatts, status.state != .discharging {
            findings.append(.drainingWhilePlugged(watts: batteryWatts))
        }
        if findings.isEmpty { findings.append(.ok(negotiated: negotiated)) }
        return findings
    }
}

/// Merkt sich je Netzteil die höchste ausgehandelte Leistung.
public struct BGAdapterMemory: Codable, Equatable, Sendable {
    public static let maximumEntries = 20
    public var bestWatts: [String: Int] = [:]

    public init(bestWatts: [String: Int] = [:]) { self.bestWatts = bestWatts }

    public func best(for adapter: BGAdapterDetails?) -> Int? {
        adapter?.identity.flatMap { bestWatts[$0] }
    }

    public func observing(_ adapter: BGAdapterDetails?) -> BGAdapterMemory {
        guard let identity = adapter?.identity, let watts = adapter?.negotiatedWatts,
              watts > (bestWatts[identity] ?? 0) else { return self }
        var next = self
        if next.bestWatts[identity] == nil, next.bestWatts.count >= Self.maximumEntries {
            return self
        }
        next.bestWatts[identity] = watts
        return next
    }
}
