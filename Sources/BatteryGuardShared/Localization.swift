import Foundation

/// Übersetzt einen deutschen Quelltext anhand der vom System gewählten Sprache.
/// Fehlt eine Übersetzung, bleibt der deutsche Text erhalten.
public func BGLocalized(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, arguments: arguments)
}
