import Foundation

public enum BGSpecialPlanKind: String, Codable, CaseIterable, Sendable {
    case topUp = "topUp"
    case discharge = "discharge"
    case hold = "hold"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "topup", "top-up":
            self = .topUp
        case "discharge", "discharge-to":
            self = .discharge
        case "hold", "hold-charge":
            self = .hold
        default:
            if let kind = BGSpecialPlanKind(rawValue: raw) {
                self = kind
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unbekannter Plantyp: \(raw)")
            }
        }
    }
}

public struct BGSpecialChargePlan: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var kind: BGSpecialPlanKind
    public var targetPercent: Int
    public var createdAt: Date
    public var expiresAt: Date
    public var hasObservedPower: Bool

    public init(
        requestID: UUID = UUID(),
        kind: BGSpecialPlanKind,
        targetPercent: Int,
        createdAt: Date,
        expiresAt: Date,
        hasObservedPower: Bool = false
    ) {
        self.requestID = requestID
        self.kind = kind
        self.targetPercent = targetPercent
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.hasObservedPower = hasObservedPower
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, kind, targetPercent, createdAt, expiresAt, hasObservedPower
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try c.decode(UUID.self, forKey: .requestID)
        kind = try c.decode(BGSpecialPlanKind.self, forKey: .kind)
        targetPercent = try c.decode(Int.self, forKey: .targetPercent)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        hasObservedPower = try c.decodeIfPresent(Bool.self, forKey: .hasObservedPower) ?? false

        guard isValid else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Ungültige Parameter für SpecialChargePlan.")
            )
        }
    }

    public var isValid: Bool {
        let createdTs = createdAt.timeIntervalSince1970
        let expiresTs = expiresAt.timeIntervalSince1970
        guard createdTs.isFinite, expiresTs.isFinite,
              createdTs > 0, expiresTs > 0,
              expiresAt > createdAt,
              expiresAt.timeIntervalSince(createdAt) <= 24 * 3600 else {
            return false
        }
        switch kind {
        case .topUp:
            return targetPercent == 100
        case .discharge, .hold:
            return (10...95).contains(targetPercent)
        }
    }

    public func evaluate(context: BGSpecialPlanEvaluationContext, at now: Date = Date()) -> BGSpecialPlanOutcome {
        guard isValid else {
            return .unavailable(reason: "Ungültiger Ladeplan.")
        }

        guard now.timeIntervalSince1970.isFinite else { return .unavailable(reason: "Zeitpunkt unbekannt.") }
        if now >= expiresAt { return .complete(reason: "Zeitlimit abgelaufen.") }
        guard context.percent.map({ (0...100).contains($0) }) == true else {
            return .unavailable(reason: "Aktueller Ladestand nicht verfügbar.")
        }
        switch kind {
        case .topUp:
            var updated = self
            if context.externalPower == .connected {
                updated.hasObservedPower = true
            }

            // Topup persists at 100 until CONFIRMED disconnect after observed connected or deadline
            if updated.hasObservedPower && context.externalPower == .disconnected {
                return .complete(reason: "Netzteil nach Top-Up getrennt.")
            }

            if let percent = context.percent, percent >= 100 {
                return .active(reason: "100 % erreicht – wird gehalten bis zum Trennen des Netzteils.", plan: updated)
            }

            if context.externalPower == .connected {
                return .active(reason: "Top-Up auf 100 % aktiv.", plan: updated)
            } else if context.externalPower == .unknown {
                return .active(reason: "Top-Up aktiv (Netzteil-Status unbekannt).", plan: updated)
            } else {
                return .active(reason: "Warte auf Anschluss des Netzteils...", plan: updated)
            }

        case .discharge:
            guard context.canDisconnectAdapter && context.allowsAdapterDisconnect else {
                return .unavailable(reason: "Entladen erfordert Adapter-Steuerung und Benutzer-Erlaubnis.")
            }
            if now >= expiresAt {
                return .complete(reason: "Zeitlimit für Entladen abgelaufen.")
            }
            if let percent = context.percent, percent <= targetPercent {
                return .complete(reason: "Ziel-Ladestand (\(targetPercent) %) erreicht.")
            }
            if context.externalPower == .disconnected {
                return .complete(reason: "Netzteil getrennt (Entladen beendet).")
            }

            var updated = self
            if context.externalPower == .connected {
                updated.hasObservedPower = true
            }
            return .active(reason: "Entladen auf \(targetPercent) % aktiv.", plan: updated)

        case .hold:
            guard context.canBlockCharging else {
                return .unavailable(reason: "Hardware unterstützt keine Ladesperre.")
            }
            if now >= expiresAt {
                return .complete(reason: "Zeitlimit für Halten abgelaufen.")
            }
            var updated = self
            if context.externalPower == .connected {
                updated.hasObservedPower = true
            }
            return .active(reason: "Ladestand wird bei \(targetPercent) % gehalten.", plan: updated)
        }
    }
}

public enum BGExternalPowerSource: String, Codable, Equatable, Sendable {
    case connected
    case disconnected
    case unknown
}

public struct BGSpecialPlanEvaluationContext: Equatable, Sendable {
    public var percent: Int?
    public var externalPower: BGExternalPowerSource
    public var canBlockCharging: Bool
    public var canDisconnectAdapter: Bool
    public var allowsAdapterDisconnect: Bool

    public init(
        percent: Int?,
        externalPower: BGExternalPowerSource,
        canBlockCharging: Bool,
        canDisconnectAdapter: Bool,
        allowsAdapterDisconnect: Bool
    ) {
        self.percent = percent
        self.externalPower = externalPower
        self.canBlockCharging = canBlockCharging
        self.canDisconnectAdapter = canDisconnectAdapter
        self.allowsAdapterDisconnect = allowsAdapterDisconnect
    }
}

public enum BGSpecialPlanState: String, Codable, Equatable, Sendable {
    case active
    case complete
    case unavailable
}

public enum BGSpecialPlanOutcome: Equatable, Sendable {
    case active(reason: String, plan: BGSpecialChargePlan)
    case complete(reason: String)
    case unavailable(reason: String)

    public var state: BGSpecialPlanState {
        switch self {
        case .active: return .active
        case .complete: return .complete
        case .unavailable: return .unavailable
        }
    }

    public var reason: String {
        switch self {
        case .active(let r, _), .complete(let r), .unavailable(let r):
            return r
        }
    }

    public var updatedPlan: BGSpecialChargePlan? {
        switch self {
        case .active(_, let p):
            return p
        case .complete, .unavailable:
            return nil
        }
    }

    public var plan: BGSpecialChargePlan? { updatedPlan }
    public var isActive: Bool { state == .active }
    public var isComplete: Bool { state == .complete }
    public var isUnavailable: Bool { state == .unavailable }
}
