import Foundation

/// Übersetzt `bguard://`-Adressen in dieselben validierten Ladeaktionen wie UI, REST und Kurzbefehle.
///
/// Beispiele: `bguard://profile/desk`, `bguard://limit/60`, `bguard://pause?minutes=60`, `bguard://resume`,
/// `bguard://top-up`, `bguard://full-charge`, `bguard://protection/off`,
/// `bguard://power-mode?low=onBattery&high=off`, `bguard://led/off`.
public enum BGURLCommand {
    public static let scheme = "bguard"

    public enum ParseError: Error, Equatable, LocalizedError {
        case unsupported(String)
        public var errorDescription: String? {
            switch self { case .unsupported(let reason): BGLocalized(reason) }
        }
    }

    public static func request(for url: URL) throws -> BGChargingActionRequest {
        guard url.scheme?.lowercased() == scheme, let host = url.host()?.lowercased() else {
            throw ParseError.unsupported("Unbekannte Adresse.")
        }
        let argument = url.pathComponents.dropFirst().first
        let query = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .compactMap { item in item.value.map { (item.name.lowercased(), $0) } } ?? [], uniquingKeysWith: { _, last in last })
        func number(_ text: String?) throws -> Int {
            guard let text, let value = Int(text) else { throw ParseError.unsupported("Zahl fehlt oder ist ungültig.") }
            return value
        }
        switch host {
        case "profile":
            guard let argument, BGProfile(rawValue: argument) != nil else { throw ParseError.unsupported("Profil muss desk, everyday oder mobile sein.") }
            return BGChargingActionRequest(action: .profile, profile: argument)
        case "limit":
            let upper = try number(argument)
            guard (20...100).contains(upper) else { throw ParseError.unsupported("Ladelimit muss zwischen 20 und 100 liegen.") }
            let lower = try query["lower"].map { try number($0) } ?? max(5, upper - 5)
            let profile = try BGSavedProfile(name: BGLocalized("Eigenes Limit"), lowerLimit: lower, upperLimit: upper)
            return BGChargingActionRequest(action: .savedProfile, savedProfile: profile)
        case "pause":
            return BGChargingActionRequest(action: .pause, minutes: try query["minutes"].map { try number($0) } ?? 60)
        case "resume": return BGChargingActionRequest(action: .resume)
        case "top-up", "topup": return BGChargingActionRequest(action: .topUp, minutes: try query["minutes"].map { try number($0) })
        case "full-charge": return BGChargingActionRequest(action: .fullCharge)
        case "cancel-full-charge": return BGChargingActionRequest(action: .cancelFullCharge)
        case "protection":
            guard let argument, ["on", "off"].contains(argument) else { throw ParseError.unsupported("Schutz muss on oder off sein.") }
            return BGChargingActionRequest(action: .protection, enabled: argument == "on")
        case "power-mode":
            let low = try query["low"].map { try rule($0) }, high = try query["high"].map { try rule($0) }
            return BGChargingActionRequest(action: .powerMode, lowPowerMode: low, highPowerMode: high)
        case "led":
            guard let argument, let mode = BGMagSafeLEDMode(rawValue: argument) else { throw ParseError.unsupported("LED muss system, indicate oder off sein.") }
            return BGChargingActionRequest(action: .magsafeLED, magsafeLED: mode)
        default:
            throw ParseError.unsupported("Unbekannter Befehl.")
        }
    }

    private static func rule(_ text: String) throws -> BGPowerModeRule {
        guard let rule = BGPowerModeRule(rawValue: text) else { throw ParseError.unsupported("Energiemodus muss off, always, onBattery oder onAdapter sein.") }
        return rule
    }
}
