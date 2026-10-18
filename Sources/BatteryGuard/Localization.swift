import Foundation
import BatteryGuardShared

/// Kurzform für sichtbare Texte, die als String statt als SwiftUI-Literal vorliegen.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, arguments: arguments)
}
