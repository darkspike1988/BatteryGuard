import Foundation
import CoreLocation
import CoreWLAN
import Observation
import BatteryGuardShared

/// Wendet Netzwerkregeln an, wenn sich das verbundene WLAN ändert. Der WLAN-Name braucht unter
/// macOS die Standortfreigabe; er wird nur lokal verglichen und nicht gespeichert, außer in deinen Regeln.
@Observable
@MainActor
final class NetworkRuleMonitor: NSObject, CLLocationManagerDelegate {
    static let shared = NetworkRuleMonitor()
    static let rulesKey = "bg.networkRules"

    private(set) var currentSSID: String?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastApplied: String?
    @ObservationIgnored private var previousSSID: String?
    @ObservationIgnored private var lastPoll: Date?
    @ObservationIgnored private let locationManager = CLLocationManager()

    var rules: [BGNetworkRule] {
        get { BGNetworkRules.decode(UserDefaults.standard.data(forKey: Self.rulesKey)) }
        set { UserDefaults.standard.set(BGNetworkRules.encode(newValue), forKey: Self.rulesKey) }
    }

    override private init() {
        super.init()
        locationManager.delegate = self
        authorization = locationManager.authorizationStatus
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    /// Aus dem Statustakt aufrufen; liest den WLAN-Namen und wendet bei Wechsel die passende Regel an.
    func poll(force: Bool = false, apply: (BGProfile) -> Void) {
        // force liest den WLAN-Namen auch ohne Regeln, etwa beim Anlegen der ersten Regel.
        if force { lastPoll = nil }
        let rules = self.rules
        let now = Date()
        guard force || !rules.isEmpty, lastPoll.map({ now.timeIntervalSince($0) >= 10 }) ?? true else { return }
        lastPoll = now
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        currentSSID = ssid
        defer { previousSSID = ssid }
        if let profile = BGNetworkRules.profileToApply(previousSSID: previousSSID, currentSSID: ssid, rules: rules) {
            apply(profile)
            lastApplied = ssid
        }
    }
}
