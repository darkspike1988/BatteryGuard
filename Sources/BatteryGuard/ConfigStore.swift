import Foundation
import Observation
import BatteryGuardShared

enum AppActionError: Error, LocalizedError {
    case unsavedChanges
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsavedChanges: "Einstellungen werden noch gespeichert. Bitte erneut versuchen."
        case .saveFailed(let message): message
        }
    }
}

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
    
    var hasUnsavedChanges: Bool { hasPendingSave }

    func savedConfig() throws -> BGConfig { try BGConfigFile.read(at: configURL) }

    @discardableResult
    func performAction(_ request: BGChargingActionRequest, at now: Date = Date()) -> Bool {
        do {
            if persistenceEnabled {
                if hasPendingSave { saveConfig() }
                guard !hasPendingSave else { throw AppActionError.unsavedChanges }
                _ = try performAPIAction(request, at: now)
            } else {
                // Preview actions are pure and never contact the live service.
                config = try request.applying(to: config, at: now)
            }
            return true
        } catch {
            hasWriteError = true
            writeErrorMessage = error.localizedDescription
            return false
        }
    }

    /// The API must return success only after the shared daemon has accepted the save.
    func performAPIAction(_ request: BGChargingActionRequest, at now: Date = Date()) throws -> BGConfig {
        guard !hasPendingSave else { throw AppActionError.unsavedChanges }
        guard persistenceEnabled else { throw AppActionError.saveFailed("Vorschau kann keine Einstellungen speichern.") }
        let saved = try BGConfigFile.performAction(request, at: configURL, now: now)
        let wasInitialLoad = isInitialLoad
        isInitialLoad = true
        config = saved
        baseline = saved
        isInitialLoad = wasInitialLoad
        hasWriteError = false
        writeErrorMessage = nil
        return saved
    }

    func apply(_ profile: BGProfile) { activateProfile(profile) }

    func activateProfile(_ profile: BGProfile) {
        performAction(BGChargingActionRequest(action: .profile, profile: profile.rawValue))
    }

    func setProtectionEnabled(_ enabled: Bool) {
        performAction(BGChargingActionRequest(action: .protection, enabled: enabled))
    }

    func pause(for duration: TimeInterval) {
        guard duration.isFinite, duration >= 60, duration <= 720 * 60,
              duration.truncatingRemainder(dividingBy: 60) == 0 else {
            hasWriteError = true
            writeErrorMessage = "Eine Pause muss zwischen 1 und 720 ganzen Minuten dauern."
            return
        }
        performAction(BGChargingActionRequest(action: .pause, minutes: Int(duration / 60)))
    }

    func resumeProtection() {
        performAction(BGChargingActionRequest(action: .resume))
    }

    func startFullCharge() {
        performAction(BGChargingActionRequest(action: .fullCharge))
    }

    func cancelFullCharge(at now: Date = Date()) {
        performAction(BGChargingActionRequest(action: .cancelFullCharge), at: now)
    }

    func scheduleTravel(readyAt: Date) {
        performAction(BGChargingActionRequest(action: .travel, readyAt: readyAt))
    }

    func cancelTravel() {
        performAction(BGChargingActionRequest(action: .cancelTravel))
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
