import AppIntents
import Foundation
import BatteryGuardShared

public enum BGuardIntentAction: String, AppEnum {
    case profile, protection, pause, resume, fullCharge, cancelFullCharge, travel, cancelTravel
    case topUp, dischargeTo, holdCharge, cancelSpecial, calibration, cancelCalibration, stayAwakeUntilLimit, cancelStayAwake
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ladeaktion")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .profile: "Profil wählen", .protection: "Schutz starten oder stoppen",
        .pause: "Schutz pausieren", .resume: "Schutz fortsetzen", .fullCharge: "Einmal voll laden",
        .cancelFullCharge: "Vollladen beenden", .travel: "Reise vorbereiten", .cancelTravel: "Reise abbrechen",
        .topUp: "Top Up bis Abstecken", .dischargeTo: "Einmal entladen", .holdCharge: "Ladestand halten",
        .cancelSpecial: "Sonderaktion beenden", .calibration: "Kalibrierung starten · Hardware-Abnahme erforderlich", .cancelCalibration: "Kalibrierung abbrechen", .stayAwakeUntilLimit: "Bis zum Ladelimit wachhalten", .cancelStayAwake: "Wachhalten beenden"
    ]
    public var chargingAction: BGChargingAction {
        switch self {
        case .profile: .profile
        case .protection: .protection
        case .pause: .pause
        case .resume: .resume
        case .fullCharge: .fullCharge
        case .cancelFullCharge: .cancelFullCharge
        case .travel: .travel
        case .cancelTravel: .cancelTravel
        case .topUp: .topUp
        case .dischargeTo: .dischargeTo
        case .holdCharge: .holdCharge
        case .cancelSpecial: .cancelSpecial
        case .calibration: .calibration
        case .cancelCalibration: .cancelCalibration
        case .stayAwakeUntilLimit: .stayAwakeUntilLimit
        case .cancelStayAwake: .cancelStayAwake
        }
    }
}

public enum BGuardIntentProfile: String, AppEnum {
    case desk, everyday, mobile
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ladeprofil")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .desk: "Schreibtisch", .everyday: "Alltag", .mobile: "Unterwegs"
    ]
}

/// No REST token or running app UI is required. The service authorizes the current
/// console user and acknowledges an atomic save, not a guaranteed hardware effect.
public struct PerformChargingActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ladeaktion ausführen"
    public static let description = IntentDescription("Speichert eine Ladeaktion im B-Guard-Dienst. Hardwareabhängige Aktionen können abgelehnt werden. Nur die zur Aktion passenden Parameter ausfüllen.")
    public static let openAppWhenRun = false
    @Parameter(title: "Aktion") public var action: BGuardIntentAction
    @Parameter(title: "Profil") public var profile: BGuardIntentProfile?
    @Parameter(title: "Schutz aktiv") public var enabled: Bool?
    @Parameter(title: "Dauer in Minuten") public var minutes: Int?
    @Parameter(title: "Reisezeitpunkt") public var readyAt: Date?
    @Parameter(title: "Ziel in Prozent") public var targetPercent: Int?
    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let request = BGChargingActionRequest(action: action.chargingAction, profile: profile?.rawValue,
            enabled: enabled, minutes: minutes, readyAt: readyAt, targetPercent: targetPercent)
        let saved = try BatteryWriteIntentExecution.perform(request)
        return .result(value: String(decoding: try BGJSON.encoder().encode(saved), as: UTF8.self))
    }
}

public enum BatteryWriteIntentExecution {
    public static func perform(_ request: BGChargingActionRequest) throws -> BGConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: BGPaths.status))
        let status = try BGJSON.decoder().decode(BGStatus.self, from: data)
        let age = Date().timeIntervalSince(status.updatedAt)
        guard (-5...60).contains(age),
              status.daemonVersion.compare(AppVersion.requiredDaemon, options: .numeric) != .orderedAscending else {
            throw BGConfigIPCError.rejected("Der B-Guard-Dienst fehlt, ist veraltet oder antwortet nicht. Bitte unter Einstellungen aktualisieren.")
        }
        return try BGConfigClient.performAction(request)
    }
}

public struct ReadChargingConfigurationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ladeprofil und Aufträge lesen"
    public static let openAppWhenRun = false
    public init() {}
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let config = try BGConfigFile.read(at: URL(fileURLWithPath: BGPaths.config))
        return .result(value: String(decoding: try BGJSON.encoder().encode(config), as: UTF8.self))
    }
}

public struct SavedChargingProfileEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Gespeichertes Ladeprofil")
    public static let defaultQuery = SavedChargingProfileQuery()
    public let id: UUID
    public let name: String
    public let lower: Int
    public let upper: Int
    public let activeDischarge: Bool
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(lower)–\(upper) % · \(activeDischarge ? "Aktives Entladen" : "Ladeprofil")")
    }
    public init(_ profile: BGSavedProfile) {
        id = profile.id; name = profile.name; lower = profile.lowerLimit; upper = profile.upperLimit; activeDischarge = profile.activeDischargeAboveUpper
    }
}

public struct SavedChargingProfileQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [UUID]) async throws -> [SavedChargingProfileEntity] {
        let profiles = try await Self.profiles()
        return profiles.filter { identifiers.contains($0.id) }.map(SavedChargingProfileEntity.init)
    }
    public func suggestedEntities() async throws -> [SavedChargingProfileEntity] {
        try await Self.profiles().map(SavedChargingProfileEntity.init)
    }
    static func profiles() async throws -> [BGSavedProfile] {
        try await MainActor.run {
            let url = SavedProfileStore.defaultProfilesURL
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try BGSavedProfileCollection.importData(SavedProfileStore.readBoundedData(from: url)).profiles
        }
    }
}

public struct ApplySavedProfileIntent: AppIntent {
    public static let title: LocalizedStringResource = "Gespeichertes Ladeprofil anwenden"
    public static let openAppWhenRun = false
    @Parameter(title: "Profil") public var profile: SavedChargingProfileEntity
    public init() {}
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let selected = try await SavedChargingProfileQuery.profiles().first(where: { $0.id == profile.id }) else {
            throw BGChargingActionError.invalidRequest("Dieses Profil wurde gelöscht. Bitte ein vorhandenes Profil wählen.")
        }
        let saved = try BatteryWriteIntentExecution.perform(.init(action: .savedProfile, savedProfile: selected))
        return .result(value: String(decoding: try BGJSON.encoder().encode(saved), as: UTF8.self))
    }
}
