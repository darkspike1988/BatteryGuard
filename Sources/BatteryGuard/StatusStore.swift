import Foundation
import Observation
import BatteryGuardShared

@Observable
@MainActor
final class StatusStore: Sendable {
    var status: BGStatus = BGStatus.unavailable
    var isDaemonActive: Bool = false
    
    var supportsChargingPlans: Bool {
        isDaemonActive && status.daemonVersion.compare("0.2.0", options: .numeric) != .orderedAscending
    }

    var daemonNeedsUpdate: Bool {
        return isDaemonActive && status.daemonVersion.compare(AppVersion.requiredDaemon, options: .numeric) == .orderedAscending
    }

    var onFreshStatus: (@MainActor (BGStatus) -> Void)?

    var configRefresh: (@MainActor () -> Void)?

    var configProvider: (@MainActor () -> BGConfig)?
    
    private var pollingTask: Task<Void, Never>?
    
    init(startImmediately: Bool = true) {
        refreshStatus()
        if startImmediately {
            startPolling()
        }
    }
    
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.refreshStatus()
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    func refreshStatus() {
        configRefresh?()
        let statusPath = BGPaths.status
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: statusPath) else {
            self.isDaemonActive = false
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statusPath))
            let decoded = try BGJSON.decoder().decode(BGStatus.self, from: data)
            if self.status != decoded { self.status = decoded }
            
            let age = Date().timeIntervalSince(decoded.updatedAt)
            self.isDaemonActive = (age >= -5.0 && age <= 60.0)
            
            if isDaemonActive { onFreshStatus?(decoded) }

            if isDaemonActive, let config = configProvider?() {
                NotificationManager.shared.checkNotifications(status: decoded, config: config)
            }
        } catch {
            self.isDaemonActive = false
        }
    }
    
    static var preview: StatusStore {
        let store = StatusStore(startImmediately: false)
        var s = BGStatus()
        s.nativeChargeLimit = 100
        s.percent = 78
        s.pluggedIn = true
        s.isChargingHardware = false
        s.state = .holding
        s.temperatureCelsius = 31.4
        s.cycleCount = 142
        s.healthPercent = 96
        s.watts = 0
        s.daemonVersion = "0.2.0"
        s.updatedAt = Date()
        s.message = "Dein Akku bleibt im Ladebereich von 75–80 %."
        store.status = s
        store.isDaemonActive = true
        return store
    }
}

extension BGStatus {
    static var unavailable: BGStatus {
        var s = BGStatus()
        s.daemonVersion = "–"
        s.updatedAt = Date.distantPast
        s.message = "Keine aktuellen Messwerte verfügbar"
        return s
    }
}
