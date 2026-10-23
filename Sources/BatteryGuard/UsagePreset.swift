import Foundation
import BatteryGuardShared

/// Antwort auf „Wie nutzt du deinen Mac meistens?“ im Einrichtungsassistenten.
enum UsagePreset: String, CaseIterable, Identifiable {
    case desk, mixed, mobile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .desk: L("Meist am Schreibtisch, fast immer am Netzteil")
        case .mixed: L("Mal am Netzteil, mal unterwegs")
        case .mobile: L("Viel unterwegs, oft auf Akku")
        }
    }

    var profile: BGProfile {
        switch self {
        case .desk: .desk
        case .mixed: .everyday
        case .mobile: .mobile
        }
    }
}
