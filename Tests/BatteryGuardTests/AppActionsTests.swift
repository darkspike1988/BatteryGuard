import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

@MainActor
struct AppActionsTests {
    private func fixture() throws -> (ConfigStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        return (ConfigStore(configURL: url), directory)
    }

    @Test func userActionsPersistAndReturnToProfile() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.apply(.desk)
        store.pause(for: 3600)
        #expect(store.config.isPaused(at: Date()))
        store.resumeProtection()
        store.startFullCharge()
        #expect(store.config.chargeToFullOnce)
        #expect(store.config.fullChargeUntil != nil)
        store.cancelFullCharge()
        #expect(!store.config.chargeToFullOnce)
        let ready = Date().addingTimeInterval(12 * 3600)
        store.scheduleTravel(readyAt: ready)
        store.flushPendingSave()
        let persisted = try BGJSON.decoder().decode(BGConfig.self, from: Data(contentsOf: directory.appendingPathComponent("config.json")))
        #expect(persisted.upperLimit == 60)
        #expect(persisted.lowerLimit == 55)
        #expect(abs(persisted.travelReadyAt!.timeIntervalSince(ready)) < 1)
        #expect(!store.hasWriteError)
    }

    @Test func externalDaemonChangesReloadWithoutClobberingPendingEdit() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.config.upperLimit = 90
        var external = BGConfig(); external.upperLimit = 70
        try BGJSON.encoder().encode(external).write(to: directory.appendingPathComponent("config.json"))
        store.loadConfig()
        #expect(store.config.upperLimit == 90)
        store.flushPendingSave()
        external.chargeToFullOnce = false
        external.upperLimit = 70
        try BGJSON.encoder().encode(external).write(to: directory.appendingPathComponent("config.json"))
        store.loadConfig()
        #expect(store.config.upperLimit == 70)
    }

    @Test func failedSaveKeepsEditsUntilSuccessfulRetry() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        store.config.upperLimit = 90
        try FileManager.default.removeItem(at: url)
        // A directory at the file path reliably forces a write failure, even as root.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        store.flushPendingSave()
        #expect(store.hasWriteError)
        try FileManager.default.removeItem(at: url)
        var external = BGConfig(); external.upperLimit = 70
        try BGJSON.encoder().encode(external).write(to: url)
        store.loadConfig()
        #expect(store.config.upperLimit == 90)
        store.flushPendingSave()
        #expect(!store.hasWriteError)
        #expect(try BGJSON.decoder().decode(BGConfig.self, from: Data(contentsOf: url)).upperLimit == 90)
    }

    @Test func menuActionsActivateProfilesAndToggleProtection() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.config.mode = .native
        store.startFullCharge()
        store.activateProfile(.desk)
        #expect(store.config.mode == .auto)
        #expect(store.config.upperLimit == 60)
        #expect(!store.config.chargeToFullOnce)
        store.pause(for: 3600)
        store.setProtectionEnabled(true)
        #expect(store.config.enabled && store.config.pauseUntil == nil)
        store.setProtectionEnabled(false)
        #expect(!store.config.effective(at: Date()).enabled)
        store.flushPendingSave()
    }

    @Test func savingLimitDoesNotResurrectCompletedFullCharge() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        store.startFullCharge()
        store.flushPendingSave()
        store.config.upperLimit = 90
        try BGConfigFile.update(at: url) { config in
            config.chargeToFullOnce = false
            config.fullChargeUntil = nil
        }
        store.flushPendingSave()
        #expect(store.config.upperLimit == 90)
        #expect(!store.config.chargeToFullOnce)
        #expect(store.config.fullChargeUntil == nil)
    }

    @Test func timedActionsRequireUpdatedLiveDaemon() {
        let status = StatusStore(startImmediately: false)
        status.isDaemonActive = true
        status.status.daemonVersion = "0.1.0"
        #expect(!status.supportsChargingPlans)
        status.status.daemonVersion = "0.3.0"
        #expect(!status.supportsChargingPlans)
        #expect(status.daemonNeedsUpdate)
        status.status.daemonVersion = AppVersion.requiredDaemon
        #expect(status.supportsChargingPlans)
        #expect(!status.daemonNeedsUpdate)
        status.isDaemonActive = false
        #expect(!status.supportsChargingPlans)
    }

    @Test func cancellingFullChargePreservesFutureTravelAndRemovesActiveTravel() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let future = now.addingTimeInterval(12 * 3600)
        store.scheduleTravel(readyAt: future)
        store.startFullCharge()
        store.cancelFullCharge(at: now)
        #expect(!store.config.chargeToFullOnce)
        #expect(store.config.fullChargeUntil == nil)
        #expect(store.config.travelReadyAt.map { abs($0.timeIntervalSince(future)) < 1 } == true)
        store.flushPendingSave()
        let persistedFuture = try #require(BGConfigFile.read(at: directory.appendingPathComponent("config.json")).travelReadyAt)
        #expect(abs(persistedFuture.timeIntervalSince(future)) < 1)

        store.scheduleTravel(readyAt: now.addingTimeInterval(3600))
        #expect(store.config.effective(at: now).chargeToFullOnce)
        store.cancelFullCharge(at: now)
        #expect(store.config.travelReadyAt == nil)
        #expect(!store.config.effective(at: now).chargeToFullOnce)
        store.flushPendingSave()
        #expect(try BGConfigFile.read(at: directory.appendingPathComponent("config.json")).travelReadyAt == nil)
    }

    @Test func desktopFallbackRecognizesActualDaemonDecision() {
        var status = BGStatus()
        status.state = .disabled
        status.message = "Monitor-/Deckelschutz: Netzteil bleibt verbunden. Ohne separate Ladesperre übernimmt macOS das Ladelimit."
        #expect(status.usesNativeDesktopFallback)
        status.state = .unsupported
        #expect(!status.usesNativeDesktopFallback)
        status.state = .disabled
        status.message = "Batterieschutz deaktiviert"
        #expect(!status.usesNativeDesktopFallback)
    }

    @Test func previewActionsNeverWrite() throws {
        let (live, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let before = try Data(contentsOf: url)
        let preview = ConfigStore(loadImmediately: false, persistenceEnabled: false, configURL: url)
        preview.apply(.mobile)
        preview.startFullCharge()
        preview.flushPendingSave()
        preview.saveConfig()
        #expect(try Data(contentsOf: url) == before)
        #expect(live.config.upperLimit == 80)
    }
}
