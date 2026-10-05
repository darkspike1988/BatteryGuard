import Foundation

// MARK: - Phases & Commands

public enum BGCalibrationPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case initialCharge
    case discharge
    case recharge
    case fullHold
}

public enum BGCalibrationCommand: String, Codable, Equatable, Sendable, CaseIterable {
    case charge
    case discharge
    case hold
}

public enum BGExternalPowerState: String, Codable, Equatable, Sendable, CaseIterable {
    case connected
    case disconnected
    case unknown
}

public typealias BGExternalPower = BGExternalPowerState

// MARK: - Context

public struct BGCalibrationContext: Codable, Equatable, Sendable {
    public var percent: Int?
    public var externalPower: BGExternalPowerState
    public var temperatureCelsius: Double?
    public var heatThreshold: Int
    public var heatActive: Bool
    public var hardwareVerified: Bool
    public var adapterDisabledByUs: Bool

    public init(
        percent: Int?,
        externalPower: BGExternalPowerState,
        temperatureCelsius: Double?,
        heatThreshold: Int,
        heatActive: Bool,
        hardwareVerified: Bool,
        adapterDisabledByUs: Bool
    ) {
        self.percent = percent
        self.externalPower = externalPower
        self.temperatureCelsius = temperatureCelsius
        self.heatThreshold = heatThreshold
        self.heatActive = heatActive
        self.hardwareVerified = hardwareVerified
        self.adapterDisabledByUs = adapterDisabledByUs
    }
}

// MARK: - Outcome

public enum BGCalibrationOutcome: Codable, Equatable, Sendable {
    case active(updatedPlan: BGCalibrationPlan, command: BGCalibrationCommand)
    case paused(updatedPlan: BGCalibrationPlan, reason: String)
    case complete(reason: String)
    case unavailable(reason: String)
}

// MARK: - Calibration Plan

public struct BGCalibrationPlan: Codable, Equatable, Sendable {
    public static let maxDuration: TimeInterval = 72 * 3600
    public static let fullHoldDuration: TimeInterval = 3600

    public var requestID: UUID
    public var phase: BGCalibrationPhase
    public var createdAt: Date
    public var expiresAt: Date
    public var phaseStartedAt: Date
    public var fullHoldStartedAt: Date?
    public var previouslyObservedPower: Bool

    // MARK: CodingKeys & Strict Decode

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case requestID
        case phase
        case createdAt
        case expiresAt
        case phaseStartedAt
        case fullHoldStartedAt
        case previouslyObservedPower
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    public init(
        requestID: UUID = UUID(),
        phase: BGCalibrationPhase = .initialCharge,
        createdAt: Date,
        expiresAt: Date? = nil,
        phaseStartedAt: Date? = nil,
        fullHoldStartedAt: Date? = nil,
        previouslyObservedPower: Bool = false
    ) {
        self.requestID = requestID
        self.phase = phase
        self.createdAt = createdAt
        let maxAllowedExpiry = createdAt.addingTimeInterval(Self.maxDuration)
        if let exp = expiresAt {
            self.expiresAt = exp
        } else {
            self.expiresAt = maxAllowedExpiry
        }
        self.phaseStartedAt = phaseStartedAt ?? createdAt
        self.fullHoldStartedAt = fullHoldStartedAt
        self.previouslyObservedPower = previouslyObservedPower
    }

    /// Explicit manually-started calibration plan factory.
    public static func manuallyStarted(
        requestID: UUID = UUID(),
        at startDate: Date,
        duration: TimeInterval = 72 * 3600
    ) -> BGCalibrationPlan {
        let cappedDuration = min(duration, maxDuration)
        return BGCalibrationPlan(
            requestID: requestID,
            phase: .initialCharge,
            createdAt: startDate,
            expiresAt: startDate.addingTimeInterval(cappedDuration),
            phaseStartedAt: startDate,
            fullHoldStartedAt: nil,
            previouslyObservedPower: false
        )
    }

    // MARK: - Strict Decodable

    public init(from decoder: Decoder) throws {
        // Enforce rejection of unknown fields
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let allowedKeyNames = Set(CodingKeys.allCases.map(\.stringValue))
        for key in dynamicContainer.allKeys {
            if !allowedKeyNames.contains(key.stringValue) {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath + [key],
                        debugDescription: "Unknown field '\(key.stringValue)' rejected by strict decode"
                    )
                )
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let requestID = try container.decode(UUID.self, forKey: .requestID)
        let phase = try container.decode(BGCalibrationPhase.self, forKey: .phase)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        let phaseStartedAt = try container.decode(Date.self, forKey: .phaseStartedAt)
        let fullHoldStartedAt = try container.decodeIfPresent(Date.self, forKey: .fullHoldStartedAt)
        let previouslyObservedPower = try container.decodeIfPresent(Bool.self, forKey: .previouslyObservedPower) ?? false

        // Invariant validations
        guard expiresAt > createdAt else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.expiresAt],
                    debugDescription: "expiresAt must be strictly after createdAt"
                )
            )
        }

        guard expiresAt.timeIntervalSince(createdAt) <= Self.maxDuration + 0.001 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.expiresAt],
                    debugDescription: "expiresAt exceeds maximum 72h limit from createdAt"
                )
            )
        }

        guard phaseStartedAt >= createdAt else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.phaseStartedAt],
                    debugDescription: "phaseStartedAt cannot be before createdAt"
                )
            )
        }

        guard phaseStartedAt <= expiresAt else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.phaseStartedAt],
                    debugDescription: "phaseStartedAt cannot be after expiresAt"
                )
            )
        }

        if phase == .fullHold {
            if let holdStart = fullHoldStartedAt, !(holdStart >= phaseStartedAt && holdStart <= expiresAt) {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath + [CodingKeys.fullHoldStartedAt],
                        debugDescription: "fullHoldStartedAt must be within phase bounds"
                    )
                )
            }
        } else {
            guard fullHoldStartedAt == nil else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath + [CodingKeys.fullHoldStartedAt],
                        debugDescription: "fullHoldStartedAt must be nil when not in fullHold phase"
                    )
                )
            }
        }

        self.requestID = requestID
        self.phase = phase
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.phaseStartedAt = phaseStartedAt
        self.fullHoldStartedAt = fullHoldStartedAt
        self.previouslyObservedPower = previouslyObservedPower
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(phase, forKey: .phase)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(phaseStartedAt, forKey: .phaseStartedAt)
        try container.encodeIfPresent(fullHoldStartedAt, forKey: .fullHoldStartedAt)
        try container.encode(previouslyObservedPower, forKey: .previouslyObservedPower)
    }

    // MARK: - Identity Helpers

    /// Pure comparison helper to ensure the updated plan matches the latest active request ID,
    /// protecting against stale updates from renewed requests.
    public func matches(requestID: UUID) -> Bool {
        self.requestID == requestID
    }

    public func isSameRequest(as other: BGCalibrationPlan) -> Bool {
        self.requestID == other.requestID
    }

    public static func isLatestIdentity(plan: BGCalibrationPlan, expectedRequestID: UUID) -> Bool {
        plan.requestID == expectedRequestID
    }

    // MARK: - Evaluation Engine

    public func evaluate(context: BGCalibrationContext, at date: Date) -> BGCalibrationOutcome {
        guard date.timeIntervalSince1970.isFinite, createdAt.timeIntervalSince1970.isFinite,
              expiresAt > createdAt, expiresAt.timeIntervalSince(createdAt) <= Self.maxDuration,
              phaseStartedAt >= createdAt, phaseStartedAt <= expiresAt else {
            return .unavailable(reason: "Invalid calibration time bounds")
        }
        // 1. Expiry check: window expiration completes plan
        if date >= expiresAt {
            return .complete(reason: "Calibration plan expired")
        }

        // 2. Hardware backend verification check
        guard context.hardwareVerified else {
            return .unavailable(reason: "Hardware backend unverified")
        }

        var updated = self

        // 3. Time sanity / clock backward check (never credit)
        if date < updated.phaseStartedAt || date < updated.createdAt {
            if updated.phase == .fullHold {
                updated.fullHoldStartedAt = nil
            }
            return .paused(updatedPlan: updated, reason: "Clock moved backward")
        }

        if updated.phase == .fullHold, let holdStart = updated.fullHoldStartedAt, date < holdStart {
            updated.fullHoldStartedAt = nil
            return .paused(updatedPlan: updated, reason: "Clock moved backward during full hold")
        }

        // 4. Record observed external power
        if context.externalPower == .connected {
            updated.previouslyObservedPower = true
        }

        // 5. External power constraints
        switch context.externalPower {
        case .disconnected:
            if updated.phase == .fullHold {
                updated.fullHoldStartedAt = nil
            }
            return .paused(updatedPlan: updated, reason: "External power disconnected; awaiting connection")

        case .unknown:
            let isAllowed = (updated.phase == .discharge && context.adapterDisabledByUs && updated.previouslyObservedPower)
            if !isAllowed {
                if updated.phase == .fullHold {
                    updated.fullHoldStartedAt = nil
                }
                return .paused(updatedPlan: updated, reason: "External power unknown; restoring normal power not guessed unplugged")
            }

        case .connected:
            break
        }

        // 6. Heat / temperature constraints
        let isTempOver = context.heatThreshold > 0 && (context.temperatureCelsius.map { $0.isFinite && $0 >= Double(context.heatThreshold) } ?? false)
        let isMissingTempAfterHeat = context.heatActive && context.temperatureCelsius == nil
        let heatTriggered = context.heatActive || isTempOver || isMissingTempAfterHeat

        if heatTriggered {
            if updated.phase == .fullHold {
                updated.fullHoldStartedAt = nil
            }
            let reason: String
            if isMissingTempAfterHeat {
                reason = "Temperature sensor unavailable after heat active; staying paused"
            } else if context.heatActive {
                reason = "Heat mitigation active"
            } else {
                reason = "Battery temperature exceeds threshold"
            }
            return .paused(updatedPlan: updated, reason: reason)
        }

        guard let temperature = context.temperatureCelsius, temperature.isFinite else {
            if updated.phase == .fullHold { updated.fullHoldStartedAt = nil }
            return .paused(updatedPlan: updated, reason: "Temperature sensor unknown")
        }
        // 7. Sensor check (percentage)
        guard let percent = context.percent, (0...100).contains(percent) else {
            if updated.phase == .fullHold {
                updated.fullHoldStartedAt = nil
            }
            return .paused(updatedPlan: updated, reason: "Battery percentage unknown")
        }

        // 8. Phase transitions & commands
        switch updated.phase {
        case .initialCharge:
            if percent >= 100 {
                updated.phase = .discharge
                updated.phaseStartedAt = date
                updated.fullHoldStartedAt = nil
                return .active(updatedPlan: updated, command: .discharge)
            } else {
                return .active(updatedPlan: updated, command: .charge)
            }

        case .discharge:
            if percent <= 10 {
                updated.phase = .recharge
                updated.phaseStartedAt = date
                updated.fullHoldStartedAt = nil
                return .active(updatedPlan: updated, command: .charge)
            } else {
                return .active(updatedPlan: updated, command: .discharge)
            }

        case .recharge:
            if percent >= 100 {
                updated.phase = .fullHold
                updated.phaseStartedAt = date
                updated.fullHoldStartedAt = date
                return .active(updatedPlan: updated, command: .hold)
            } else {
                return .active(updatedPlan: updated, command: .charge)
            }

        case .fullHold:
            if percent < 100 {
                updated.fullHoldStartedAt = nil
                return .active(updatedPlan: updated, command: .charge)
            }
            if updated.fullHoldStartedAt == nil {
                updated.fullHoldStartedAt = date
            }
            guard let holdStart = updated.fullHoldStartedAt else { return .unavailable(reason: "Hold timer unavailable") }
            let elapsed = date.timeIntervalSince(holdStart)
            if elapsed >= Self.fullHoldDuration {
                return .complete(reason: "Full hold of 1 hour continuous hold completed")
            } else {
                return .active(updatedPlan: updated, command: .hold)
            }
        }
    }
}
