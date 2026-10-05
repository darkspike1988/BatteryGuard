import Foundation

// MARK: - Validation & Error Types

/// Errors thrown when validating, importing, or exporting profiles and collections.
public enum BGSavedProfileError: LocalizedError, Equatable, Sendable {
    case emptyName
    case nameTooLong(count: Int, max: Int)
    case invalidLowerLimit(Int)
    case invalidUpperLimit(Int)
    case upperLimitNotGreaterThanLower(lower: Int, upper: Int)
    case invalidHeatProtection(Int)
    case unsupportedSchemaVersion(Int)
    case tooManyProfiles(count: Int, max: Int)
    case duplicateProfileID(UUID)
    case duplicateProfileName(String)
    case payloadTooLarge(bytes: Int, maxBytes: Int)
    case unknownProfileField(String)
    case unknownCollectionField(String)
    case invalidSchema(String)
    case invalidEncoding
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Profile name cannot be empty."
        case .nameTooLong(let count, let max):
            return "Profile name has \(count) characters, exceeding the maximum allowed length of \(max)."
        case .invalidLowerLimit(let val):
            return "Lower limit \(val)% is outside the allowed range of 5% to 95%."
        case .invalidUpperLimit(let val):
            return "Upper limit \(val)% is outside the allowed range of 20% to 100%."
        case .upperLimitNotGreaterThanLower(let lower, let upper):
            return "Upper limit (\(upper)%) must be strictly greater than lower limit (\(lower)%)."
        case .invalidHeatProtection(let val):
            return "Heat protection temperature (\(val)°C) must be 0 (disabled) or between 30°C and 50°C."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported profile schema version \(version). Expected version 1."
        case .tooManyProfiles(let count, let max):
            return "Collection contains \(count) profiles, exceeding the maximum allowed limit of \(max)."
        case .duplicateProfileID(let id):
            return "Duplicate profile ID found: \(id)."
        case .duplicateProfileName(let name):
            return "Duplicate profile name found (case-insensitive): '\(name)'."
        case .payloadTooLarge(let bytes, let maxBytes):
            return "Import data size (\(bytes) bytes) exceeds maximum allowed size of \(maxBytes) bytes (256 KiB)."
        case .unknownProfileField(let key):
            return "Unknown profile field '\(key)' is not allowed in profile schema."
        case .unknownCollectionField(let key):
            return "Unknown collection field '\(key)' is not allowed in collection schema."
        case .invalidSchema(let details):
            return "Invalid profile schema format: \(details)."
        case .invalidEncoding:
            return "Import payload is not valid UTF-8 data."
        case .encodingFailed:
            return "Failed to encode profile collection to UTF-8."
        }
    }
}

public typealias BGSavedProfileValidationError = BGSavedProfileError

// MARK: - Dynamic Coding Key Helper

private struct BGDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Saved Profile Model

/// Immutable, validated user-defined charging profile.
public struct BGSavedProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let lowerLimit: Int
    public let upperLimit: Int
    public let heatProtectionCelsius: Int
    public let activeDischargeAboveUpper: Bool

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case lowerLimit
        case upperLimit
        case heatProtectionCelsius
        case activeDischargeAboveUpper
    }

    /// Explicit throwing initializer enforcing strict validation without silent clamping.
    public init(
        id: UUID = UUID(),
        name: String,
        lowerLimit: Int,
        upperLimit: Int,
        heatProtectionCelsius: Int = 0,
        activeDischargeAboveUpper: Bool = false
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BGSavedProfileError.emptyName
        }
        guard trimmed.count <= 60 else {
            throw BGSavedProfileError.nameTooLong(count: trimmed.count, max: 60)
        }
        guard (5...95).contains(lowerLimit) else {
            throw BGSavedProfileError.invalidLowerLimit(lowerLimit)
        }
        guard (20...100).contains(upperLimit) else {
            throw BGSavedProfileError.invalidUpperLimit(upperLimit)
        }
        guard upperLimit > lowerLimit else {
            throw BGSavedProfileError.upperLimitNotGreaterThanLower(lower: lowerLimit, upper: upperLimit)
        }
        guard heatProtectionCelsius == 0 || (30...50).contains(heatProtectionCelsius) else {
            throw BGSavedProfileError.invalidHeatProtection(heatProtectionCelsius)
        }

        self.id = id
        self.name = trimmed
        self.lowerLimit = lowerLimit
        self.upperLimit = upperLimit
        self.heatProtectionCelsius = heatProtectionCelsius
        self.activeDischargeAboveUpper = activeDischargeAboveUpper
    }

    public init(from decoder: Decoder) throws {
        // Enforce strict unknown field rejection to avoid secrets or unwhitelisted data leakage
        let rawContainer = try decoder.container(keyedBy: BGDynamicCodingKey.self)
        let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        for key in rawContainer.allKeys {
            if !allowedKeys.contains(key.stringValue) {
                throw BGSavedProfileError.unknownProfileField(key.stringValue)
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let lowerLimit = try container.decode(Int.self, forKey: .lowerLimit)
        let upperLimit = try container.decode(Int.self, forKey: .upperLimit)
        let heat = try container.decodeIfPresent(Int.self, forKey: .heatProtectionCelsius) ?? 0
        let activeDischarge = try container.decodeIfPresent(Bool.self, forKey: .activeDischargeAboveUpper) ?? false

        try self.init(
            id: id,
            name: name,
            lowerLimit: lowerLimit,
            upperLimit: upperLimit,
            heatProtectionCelsius: heat,
            activeDischargeAboveUpper: activeDischarge
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lowerLimit, forKey: .lowerLimit)
        try container.encode(upperLimit, forKey: .upperLimit)
        try container.encode(heatProtectionCelsius, forKey: .heatProtectionCelsius)
        try container.encode(activeDischargeAboveUpper, forKey: .activeDischargeAboveUpper)
    }

    /// Applies this profile's parameters to a `BGConfig`.
    ///
    /// Semantics:
    /// - `enabled` is set to `true`.
    /// - Updates `lowerLimit`, `upperLimit`, `heatProtectionCelsius`, and `activeDischargeAboveUpper`.
    /// - Preserves `.auto` or `.pendulum` mode. If mode is `.native` or `.direct`, switches to `.auto`
    ///   so that custom thresholds can be properly managed.
    /// - Preserves unrelated settings such as `magsafeLed`.
    /// - Clears temporary pauses (`pauseUntil`) and existing full-charge requests (`chargeToFullOnce`,
    ///   `fullChargeUntil`, `fullChargeRequestID`).
    /// - Preserves future travel reservations (`travelReadyAt`, `travelRequestID`).
    ///
    /// Note on Phase 3 special actions: Manual special action fields from future phases (P3) are not
    /// yet present in this worktree. Callers applying this profile should ensure any active manual
    /// special actions are cancelled upon profile application.
    public func applying(to config: BGConfig) -> BGConfig {
        var c = config
        c.enabled = true
        c.lowerLimit = lowerLimit
        c.upperLimit = upperLimit
        c.heatProtectionCelsius = heatProtectionCelsius
        c.activeDischargeAboveUpper = activeDischargeAboveUpper

        switch c.mode {
        case .native, .direct:
            c.mode = .auto
        case .auto, .pendulum:
            break
        }

        c.specialChargePlan = nil
        c.pauseUntil = nil
        c.chargeToFullOnce = false
        c.fullChargeUntil = nil
        c.fullChargeRequestID = nil

        return c.sanitized()
    }

    /// Checks whether an existing `BGConfig` matches this profile's primary settings.
    public func matches(_ c: BGConfig) -> Bool {
        c.enabled
            && c.lowerLimit == lowerLimit
            && c.upperLimit == upperLimit
            && c.heatProtectionCelsius == heatProtectionCelsius
            && c.activeDischargeAboveUpper == activeDischargeAboveUpper
    }
}

// MARK: - Saved Profile Collection

/// Versioned collection container for profile export and import.
public struct BGSavedProfileCollection: Codable, Equatable, Sendable {
    public static let currentVersion: Int = 1
    public static let maxProfilesCount: Int = 50
    public static let maxImportDataBytes: Int = 256 * 1024 // 256 KiB

    public let version: Int
    public let profiles: [BGSavedProfile]

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case profiles
    }

    public init(profiles: [BGSavedProfile], version: Int = Self.currentVersion) throws {
        guard version == Self.currentVersion else {
            throw BGSavedProfileError.unsupportedSchemaVersion(version)
        }
        guard profiles.count <= Self.maxProfilesCount else {
            throw BGSavedProfileError.tooManyProfiles(count: profiles.count, max: Self.maxProfilesCount)
        }

        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        for profile in profiles {
            if seenIDs.contains(profile.id) {
                throw BGSavedProfileError.duplicateProfileID(profile.id)
            }
            seenIDs.insert(profile.id)

            let normalizedName = profile.name.lowercased()
            if seenNames.contains(normalizedName) {
                throw BGSavedProfileError.duplicateProfileName(profile.name)
            }
            seenNames.insert(normalizedName)
        }

        self.version = version
        self.profiles = profiles
    }

    public init(from decoder: Decoder) throws {
        // Enforce strict unknown field rejection on root collection
        let rawContainer = try decoder.container(keyedBy: BGDynamicCodingKey.self)
        let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        for key in rawContainer.allKeys {
            if !allowedKeys.contains(key.stringValue) {
                throw BGSavedProfileError.unknownCollectionField(key.stringValue)
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw BGSavedProfileError.unsupportedSchemaVersion(version)
        }
        let profiles = try container.decode([BGSavedProfile].self, forKey: .profiles)
        try self.init(profiles: profiles, version: version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(profiles, forKey: .profiles)
    }

    /// Serializes the collection to formatted UTF-8 JSON data using `BGJSON.encoder()`.
    public func exportData() throws -> Data {
        try BGJSON.encoder().encode(self)
    }

    /// Serializes the collection to a formatted UTF-8 JSON string.
    public func exportJSONString() throws -> String {
        let data = try exportData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw BGSavedProfileError.encodingFailed
        }
        return string
    }

    /// Atomically imports a collection from JSON data.
    ///
    /// Rejects payloads > 256 KiB, unsupported schema versions, unknown fields, duplicate IDs,
    /// duplicate case-insensitive names, or out-of-range profile limits.
    public static func importData(_ data: Data) throws -> BGSavedProfileCollection {
        guard data.count <= Self.maxImportDataBytes else {
            throw BGSavedProfileError.payloadTooLarge(bytes: data.count, maxBytes: Self.maxImportDataBytes)
        }
        do {
            return try BGJSON.decoder().decode(BGSavedProfileCollection.self, from: data)
        } catch let error as BGSavedProfileError {
            throw error
        } catch {
            throw BGSavedProfileError.invalidSchema(error.localizedDescription)
        }
    }

    /// Atomically imports a collection from a JSON string.
    public static func importJSONString(_ jsonString: String) throws -> BGSavedProfileCollection {
        guard let data = jsonString.data(using: .utf8) else {
            throw BGSavedProfileError.invalidEncoding
        }
        return try importData(data)
    }
}
