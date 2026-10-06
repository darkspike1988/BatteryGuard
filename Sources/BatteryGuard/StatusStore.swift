import Foundation
import Observation
import BatteryGuardShared

@Observable
@MainActor
final class StatusStore: Sendable {
    var status: BGStatus = BGStatus.unavailable
    var isDaemonActive: Bool = false
    
    var supportsChargingPlans: Bool {
        isDaemonActive && status.daemonVersion.compare(AppVersion.requiredDaemon, options: .numeric) != .orderedAscending
    }

    var daemonNeedsUpdate: Bool {
        return isDaemonActive && status.daemonVersion.compare(AppVersion.requiredDaemon, options: .numeric) == .orderedAscending
    }

    var onFreshStatus: (@MainActor (BGStatus) -> Void)?

    var configRefresh: (@MainActor () -> Void)?

    var configProvider: (@MainActor () -> BGConfig)?
    
    var powerFlow: BGPowerFlowSample?
    var systemDiagnostics: BGSystemSnapshot?
    private let systemReader = SystemDiagnosticsReader()
    private var diagnosticsVisible = false
    private var isPreview = false
    func beginDiagnostics() { diagnosticsVisible = true; if !isPreview { systemDiagnostics = systemReader.read() } }
    func endDiagnostics() { diagnosticsVisible = false; systemReader.reset(); if !isPreview { systemDiagnostics = nil } }
    private let reader: @MainActor () -> BGPowerFlowSample?
    private var pollingTask: Task<Void, Never>?
    
    init(startImmediately: Bool = true, reader: @escaping @MainActor () -> BGPowerFlowSample? = { PowerFlowReader.read() }) {
        self.reader = reader
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
        if diagnosticsVisible && !isPreview { systemDiagnostics = systemReader.read() }
        configRefresh?()
        self.powerFlow = reader()
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
        let store = StatusStore(startImmediately: false, reader: { nil })
        store.isPreview = true
        let now = Date()
        store.systemDiagnostics = BGSystemSnapshot(sampledAt: now, thermalState: .nominal,
            measurements: BGBatteryMeasurements(values: [
                BGMeasurement(.cpuLoad, value: 14, source: .machCPU, sampledAt: now, quality: .derived),
                BGMeasurement(.memoryUsed, value: 6_000_000_000, source: .machMemory, sampledAt: now, quality: .derived),
                BGMeasurement(.memoryTotal, value: 16_000_000_000, source: .machMemory, sampledAt: now),
                BGMeasurement(.swapUsed, value: 0, source: .swapUsage, sampledAt: now),
                BGMeasurement(.volumeAvailable, value: 220_000_000_000, source: .volumeCapacity, sampledAt: now),
                BGMeasurement(.volumeTotal, value: 500_000_000_000, source: .volumeCapacity, sampledAt: now)
            ]), modelIdentifier: "MacBookPro18,3")
        store.powerFlow = BGPowerFlowSample(
            inputWatts: 12,
            batteryWatts: 0,
            adapterRatedWatts: 65,
            hardwarePercent: 77.6
        )
        var s = BGStatus()
        s.nativeChargeLimit = 100
        s.percent = 78
        s.pluggedIn = true
        s.isChargingHardware = false
        s.state = .holding
        s.temperatureCelsius = 31.4
        s.cycleCount = 142
        s.healthPercent = 96
        s.maxCapacityMah = 4800
        s.designCapacityMah = 5000
        s.watts = 0
        s.daemonVersion = AppVersion.requiredDaemon
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
