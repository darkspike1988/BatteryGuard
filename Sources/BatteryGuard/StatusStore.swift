import Foundation
import Observation
import BatteryGuardShared

@Observable
@MainActor
final class StatusStore: Sendable {
    var status: BGStatus = BGStatus.fallbackMock
    var isDaemonActive: Bool = false
    
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
        let statusPath = BGPaths.status
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: statusPath) else {
            self.isDaemonActive = false
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statusPath))
            let decoded = try BGJSON.decoder().decode(BGStatus.self, from: data)
            self.status = decoded
            
            let age = Date().timeIntervalSince(decoded.updatedAt)
            self.isDaemonActive = (age <= 60.0)
            
            if let config = configProvider?() {
                NotificationManager.shared.checkNotifications(status: decoded, config: config)
            }
        } catch {
            self.isDaemonActive = false
        }
    }
    
    static var preview: StatusStore {
        let store = StatusStore(startImmediately: false)
        var s = BGStatus()
        s.percent = 78
        s.pluggedIn = true
        s.isChargingHardware = false
        s.state = .holding
        s.temperatureCelsius = 31.4
        s.cycleCount = 142
        s.healthPercent = 96
        s.watts = 18.2
        s.daemonVersion = "0.1.0"
        s.updatedAt = Date()
        s.message = "Preview-Modus"
        store.status = s
        store.isDaemonActive = true
        return store
    }
}

extension BGStatus {
    static var fallbackMock: BGStatus {
        var s = BGStatus()
        s.percent = 80
        s.pluggedIn = true
        s.isChargingHardware = false
        s.state = .holding
        s.temperatureCelsius = 31.0
        s.cycleCount = 120
        s.healthPercent = 98
        s.watts = 0.0
        s.daemonVersion = "–"
        s.updatedAt = Date.distantPast
        s.message = "Dienst nicht aktiv (Fallback-Anzeige)"
        return s
    }
}
