import Foundation
import Observation
import BatteryGuardShared

@Observable
@MainActor
final class ConfigStore: Sendable {
    var config: BGConfig = BGConfig() {
        didSet {
            guard !isInitialLoad else { return }
            scheduleDebouncedSave()
        }
    }
    
    var hasWriteError: Bool = false
    var writeErrorMessage: String? = nil
    
    private var isInitialLoad: Bool = true
    private var saveTask: Task<Void, Never>?
    
    init(loadImmediately: Bool = true) {
        if loadImmediately {
            loadConfig()
        }
        self.isInitialLoad = false
    }
    
    func loadConfig() {
        let path = BGPaths.config
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            self.config = BGConfig().sanitized()
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try BGJSON.decoder().decode(BGConfig.self, from: data)
            self.config = decoded.sanitized()
            self.hasWriteError = false
            self.writeErrorMessage = nil
        } catch {
            self.config = BGConfig().sanitized()
        }
    }
    
    func scheduleDebouncedSave() {
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
        let sanitized = self.config.sanitized()
        let configURL = URL(fileURLWithPath: BGPaths.config)
        
        do {
            let data = try BGJSON.encoder().encode(sanitized)
            // Wir schreiben direkt in die Datei (ohne .atomic), 
            // da der übergeordnete Ordner root gehört (0755) und die 
            // Datei selbst 0666 hat. Atomic Save würde versuchen, eine 
            // Temp-Datei im selben Ordner zu erstellen und umzubenennen, 
            // was an fehlenden Ordner-Schreibrechten scheitert.
            try data.write(to: configURL)
            
            self.hasWriteError = false
            self.writeErrorMessage = nil
        } catch {
            self.hasWriteError = true
            self.writeErrorMessage = error.localizedDescription
        }
    }
    
    static var preview: ConfigStore {
        let store = ConfigStore(loadImmediately: false)
        var c = BGConfig()
        c.enabled = true
        c.lowerLimit = 20
        c.upperLimit = 80
        c.activeDischargeAboveUpper = false
        c.heatProtectionCelsius = 40
        c.chargeToFullOnce = false
        store.config = c
        return store
    }
}
