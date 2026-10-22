import Foundation

/// Der Dienst schreibt Statusmeldungen auf Deutsch, weil er ohne eigenes
/// Ressourcenbundle läuft. Die App übersetzt sie hier für die Anzeige.
enum StatusMessageLocalizer {
    static func localized(_ message: String) -> String {
        if message.contains(" · ") {
            return message.components(separatedBy: " · ").map(localized).joined(separator: " · ")
        }
        let missing = "\u{0}not-localized"
        let direct = Bundle.main.localizedString(forKey: message, value: missing, table: nil)
        if direct != missing { return direct }
        return pattern(message) ?? message
    }

    private static func pattern(_ message: String) -> String? {
        if let values = captures(message, #"^Hitzeschutz aktiv: ([0-9.,]+)°C – Freigabe nach Abkühlung$"#),
           let temperature = Double(values[0].replacingOccurrences(of: ",", with: ".")) {
            return L("Hitzeschutz aktiv: %.1f°C – Freigabe nach Abkühlung", temperature)
        }
        if let values = captures(message, #"^Schutz pausiert bis (.+)$"#) {
            return L("Schutz pausiert bis %@", values[0])
        }
        if let values = captures(message, #"^Einmaliges Vollladen aktiv \((\d+) %\)$"#) {
            return L("Einmaliges Vollladen aktiv (%lld %%)", Int(values[0]) ?? 0)
        }
        if let values = captures(message, #"^Aktives Entladen auf (\d+) % \(aktuell (\d+) %\)$"#),
           let target = Int(values[0]), let current = Int(values[1]) {
            return L("Aktives Entladen auf %lld %% (aktuell %lld %%)", target, current)
        }
        if let values = captures(message, #"^Ladelimit von (\d+) % erreicht$"#),
           let limit = Int(values[0]) {
            return L("Ladelimit von %lld %% erreicht", limit)
        }
        if let values = captures(message, #"^Ladelimit von (\d+) % gehalten$"#),
           let limit = Int(values[0]) {
            return L("Ladelimit von %lld %% gehalten", limit)
        }
        if let values = captures(message, #"^Laden aktiv bis (\d+) %$"#),
           let limit = Int(values[0]) {
            return L("Laden aktiv bis %lld %%", limit)
        }
        return nil
    }

    private static func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            Range(match.range(at: $0), in: text).map { String(text[$0]) }
        }
    }
}
