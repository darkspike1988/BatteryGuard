import Foundation

/// Ein Ladeprofil, das gilt, sobald der Mac mit einem bestimmten WLAN verbunden ist.
public struct BGNetworkRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var ssid: String
    public var profile: BGProfile

    public init(id: UUID = UUID(), ssid: String, profile: BGProfile) {
        self.id = id
        self.ssid = ssid
        self.profile = profile
    }
}

public enum BGNetworkRules {
    public static let maxRules = 20

    public static func decode(_ data: Data?) -> [BGNetworkRule] {
        guard let data, let rules = try? JSONDecoder().decode([BGNetworkRule].self, from: data) else { return [] }
        return Array(rules.prefix(maxRules))
    }

    public static func encode(_ rules: [BGNetworkRule]) -> Data {
        (try? JSONEncoder().encode(Array(rules.prefix(maxRules)))) ?? Data()
    }

    /// Profil für ein WLAN; Namen werden exakt verglichen, da WLAN-Namen Groß-/Kleinschreibung unterscheiden.
    public static func profile(for ssid: String?, in rules: [BGNetworkRule]) -> BGProfile? {
        guard let ssid, !ssid.isEmpty else { return nil }
        return rules.first { $0.ssid == ssid }?.profile
    }

    /// Nur beim Wechsel in ein Netzwerk mit Regel handeln, nicht bei jedem Abfragetakt.
    public static func profileToApply(previousSSID: String?, currentSSID: String?, rules: [BGNetworkRule]) -> BGProfile? {
        guard currentSSID != previousSSID else { return nil }
        return profile(for: currentSSID, in: rules)
    }
}
