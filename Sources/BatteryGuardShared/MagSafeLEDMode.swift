import Foundation

/// Bedienoberfläche für die beiden gespeicherten LED-Felder `magsafeLed` und `magsafeLedOff`.
public enum BGMagSafeLEDMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, indicate, off
    public var id: String { rawValue }
}

public extension BGConfig {
    var magsafeLedMode: BGMagSafeLEDMode {
        get { magsafeLedOff ? .off : (magsafeLed ? .indicate : .system) }
        set {
            magsafeLedOff = newValue == .off
            magsafeLed = newValue == .indicate
        }
    }
}
