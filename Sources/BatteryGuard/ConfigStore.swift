import Foundation
import Observation
import BatteryGuardShared

@Observable
@MainActor
final class ConfigStore: Sendable {
    var config: BGConfig = BGConfig() {
        didSet {
            guard !isInitialLoad, persistenceEnabled else { return }
            scheduleDebouncedSave()
        }
    }
    
    var hasWriteError: Bool = false
    var writeErrorMessage: String? = nil
    
    private let configURL: URL
    private let persistenceEnabled: Bool
    private var isInitialLoad: Bool = true
    private var saveTask: Task<Void, Never>?
    private var hasPendingSave = false
    private var baseline = BGConfig().sanitized()
    
    init(loadImmediately: Bool = true, persistenceEnabled: Bool = true,
         configURL: URL = URL(fileURLWithPath: BGPaths.config)) {
        self.configURL = configURL
        self.persistenceEnabled = persistenceEnabled
        if loadImmediately {
            loadConfig()
        }
        self.isInitialLoad = false
    }
    
    func loadConfig() {
        guard !hasPendingSave else { return }
        let wasInitialLoad = isInitialLoad
        isInitialLoad = true
        defer { isInitialLoad = wasInitialLoad }
        let path = configURL.path
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            self.config = BGConfig().sanitized()
            baseline = config
            return
        }
        
        do {
            let clean = try BGConfigFile.read(at: configURL)
            baseline = clean
            if self.config != clean { self.config = clean }
            self.hasWriteError = false
            self.writeErrorMessage = nil
        } catch {
            self.hasWriteError = true
            self.writeErrorMessage = "Konfiguration konnte nicht gelesen werden: " + error.localizedDescription
        }
    }
    
    func scheduleDebouncedSave() {
        hasPendingSave = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return // Vorzeitig abgebrochen
            }
            guard !Task.isCancelled, let self else { return }
            self.saveConfig()
        }
    }
    
    func saveConfig() {
        guard persistenceEnabled else { return }
        let sanitized = self.config.sanitized()
        
        do {
            let saved = try BGConfigFile.update(at: configURL) { latest in
                latest = sanitized.mergingEdits(since: baseline, into: latest)
            }
            let wasInitialLoad = isInitialLoad
            isInitialLoad = true
            config = saved
            baseline = saved
            isInitialLoad = wasInitialLoad
            hasPendingSave = false
            self.hasWriteError = false
            self.writeErrorMessage = nil
        } catch {
            hasPendingSave = true
            self.hasWriteError = true
            self.writeErrorMessage = error.localizedDescription
        }
    }
    
    func apply(_ profile: BGProfile) {
        activateProfile(profile)
    }

    func activateProfile(_ profile: BGProfile) {
        var next = profile.applying(to: config)
        if next.mode == .native || next.mode == .direct { next.mode = .auto }
        next.chargeToFullOnce = false
        next.fullChargeUntil = nil
        if next.isTravelCharging(at: Date()) { next.travelReadyAt = nil }
        config = next
    }

    func setProtectionEnabled(_ enabled: Bool) {
        var next = config
        next.enabled = enabled
        next.pauseUntil = nil
        if enabled && (next.mode == .native || next.mode == .direct) { next.mode = .auto }
        config = next
    }

    func pause(for duration: TimeInterval) {
        config.pauseUntil = Date().addingTimeInterval(duration)
    }

    func resumeProtection() { config.pauseUntil = nil }

    func startFullCharge() {
        var next = config
        next.enabled = true
        next.pauseUntil = nil
        next.chargeToFullOnce = true
        next.fullChargeUntil = Date().addingTimeInterval(8 * 3600)
        config = next
    }

    func cancelFullCharge() {
        config.chargeToFullOnce = false
        config.fullChargeUntil = nil
    }

    func scheduleTravel(readyAt: Date) {
        var next = config
        next.enabled = true
        next.pauseUntil = nil
        next.travelReadyAt = readyAt
        next.chargeToFullOnce = false
        next.fullChargeUntil = nil
        config = next
    }

    func flushPendingSave() {
        guard hasPendingSave else { return }
        saveTask?.cancel()
        saveConfig()
    }

    static var preview: ConfigStore {
        let store = ConfigStore(loadImmediately: false, persistenceEnabled: false)
        var c = BGConfig()
        c.enabled = true
        c.lowerLimit = 75
        c.upperLimit = 80
        c.activeDischargeAboveUpper = false
        c.heatProtectionCelsius = 40
        c.chargeToFullOnce = false
        store.config = c
        return store
    }
}
