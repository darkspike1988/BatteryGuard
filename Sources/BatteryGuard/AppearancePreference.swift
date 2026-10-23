import AppKit
import SwiftUI

/// Hell/Dunkel unabhängig vom System und eine Akzentfarbe für B-Guards Fenster.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    static let appStorageKey = "bg.appearanceMode"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Wie macOS")
        case .light: L("Hell")
        case .dark: L("Dunkel")
        }
    }

    @MainActor func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor static func applyStored() {
        (AppearancePreference(rawValue: UserDefaults.standard.string(forKey: appStorageKey) ?? "") ?? .system).apply()
    }
}

enum AccentPreference: String, CaseIterable, Identifiable {
    case system, blue, green, orange, pink, purple
    static let appStorageKey = "bg.accentColor"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Systemfarbe")
        case .blue: L("Blau")
        case .green: L("Grün")
        case .orange: L("Orange")
        case .pink: L("Pink")
        case .purple: L("Lila")
        }
    }

    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        }
    }
}
