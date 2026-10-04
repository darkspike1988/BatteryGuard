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
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try BGJSON.decoder().decode(BGConfig.self, from: data)
            let clean = decoded.sanitized()
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
            self.saveConfigAtomically()
        }
    }
    
    func saveConfigAtomically() {
        guard persistenceEnabled else { return }
        let sanitized = self.config.sanitized()
        
        do {
            let data = try BGJSON.encoder().encode(sanitized)
            // Wir schreiben direkt in die Datei (ohne .atomic), 
            // da der übergeordnete Ordner root gehört (0755) und die 
            // Datei selbst 0666 hat. Atomic Save würde versuchen, eine 
            // Temp-Datei im selben Ordner zu erstellen und umzubenennen, 
            // was an fehlenden Ordner-Schreibrechten scheitert.
            try data.write(to: configURL)
            
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
        config = profile.applying(to: config)
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
        saveConfigAtomically()
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
