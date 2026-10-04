import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

struct ChargingActionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func profileActivatesControlAndPreservesFutureTravel() throws {
        for mode in [BGMode.native, .direct, .auto, .pendulum] {
            var config = BGConfig(); config.mode = mode
            config.chargeToFullOnce = true; config.fullChargeUntil = now.addingTimeInterval(100)
            config.travelReadyAt = now.addingTimeInterval(12 * 3600)
            let applied = try BGChargingActionRequest(action: .profile, profile: "desk").applying(to: config, at: now)
            #expect(applied.mode == (mode == .pendulum ? .pendulum : .auto))
            #expect(applied.enabled && applied.lowerLimit == 55 && applied.upperLimit == 60)
            #expect(!applied.chargeToFullOnce && applied.fullChargeUntil == nil)
            #expect(applied.travelReadyAt == config.travelReadyAt)
            config.travelReadyAt = now.addingTimeInterval(3600)
            #expect(try BGChargingActionRequest(action: .profile, profile: "everyday").applying(to: config, at: now).travelReadyAt == nil)
        }
    }

    @Test func protectionStartsControlButDisablingPreservesMode() throws {
        var config = BGConfig(); config.mode = .native; config.pauseUntil = now.addingTimeInterval(100)
        let disabled = try BGChargingActionRequest(action: .protection, enabled: false).applying(to: config, at: now)
        #expect(!disabled.enabled && disabled.mode == .native && disabled.pauseUntil == nil)
        let enabled = try BGChargingActionRequest(action: .protection, enabled: true).applying(to: config, at: now)
        #expect(enabled.enabled && enabled.mode == .auto && enabled.pauseUntil == nil)
    }

    @Test func pauseBoundariesAndUnsupportedModes() throws {
        for minutes in [1, 720] {
            let paused = try BGChargingActionRequest(action: .pause, minutes: minutes).applying(to: BGConfig(), at: now)
            #expect(paused.pauseUntil == now.addingTimeInterval(Double(minutes) * 60))
            #expect(try BGChargingActionRequest(action: .resume).applying(to: paused, at: now).pauseUntil == nil)
        }
        for minutes in [0, -1, 721, Int.max] {
            #expect(throws: BGChargingActionError.self) {
                try BGChargingActionRequest(action: .pause, minutes: minutes).applying(to: BGConfig(), at: now)
            }
        }
        for mode in [BGMode.native, .direct] {
            var config = BGConfig(); config.mode = mode
            for action in [BGChargingAction.pause, .resume, .fullCharge, .travel] {
                let request = BGChargingActionRequest(action: action,
                    minutes: action == .pause ? 1 : nil,
                    readyAt: action == .travel ? now.addingTimeInterval(3600) : nil)
                #expect(throws: BGChargingActionError.unsupportedMode) { try request.applying(to: config, at: now) }
            }
        }
    }

    @Test func travelAndFullChargeRespectDeadlinesAndCancellation() throws {
        let future = now.addingTimeInterval(12 * 3600)
        let planned = try BGChargingActionRequest(action: .travel, readyAt: future).applying(to: BGConfig(), at: now)
        let full = try BGChargingActionRequest(action: .fullCharge).applying(to: planned, at: now)
        #expect(full.fullChargeUntil == now.addingTimeInterval(8 * 3600))
        #expect(full.travelReadyAt == future && full.chargeToFullOnce)
        let cancelled = try BGChargingActionRequest(action: .cancelFullCharge).applying(to: full, at: now)
        #expect(!cancelled.chargeToFullOnce && cancelled.fullChargeUntil == nil && cancelled.travelReadyAt == future)
        let active = try BGChargingActionRequest(action: .travel, readyAt: now.addingTimeInterval(3600)).applying(to: full, at: now)
        #expect(try BGChargingActionRequest(action: .cancelFullCharge).applying(to: active, at: now).travelReadyAt == nil)
        #expect(try BGChargingActionRequest(action: .cancelTravel).applying(to: full, at: now).chargeToFullOnce)
        for date in [now, now.addingTimeInterval(-1), now.addingTimeInterval(30 * 24 * 3600 + 1)] {
            #expect(throws: BGChargingActionError.self) {
                try BGChargingActionRequest(action: .travel, readyAt: date).applying(to: BGConfig(), at: now)
            }
        }
        #expect(try BGChargingActionRequest(action: .travel, readyAt: now.addingTimeInterval(30 * 24 * 3600)).applying(to: BGConfig(), at: now).travelReadyAt != nil)
    }

    @Test func jsonRejectsUnknownAndUnrelatedFieldsAndWrongTypes() throws {
        for json in [
            "{\"action\":\"resume\",\"enabled\":null}",
            "{\"action\":\"profile\",\"profile\":\"desk\",\"unknown\":1}",
            "{\"action\":\"profile\",\"profile\":\"invalid\"}",
            "{\"action\":\"protection\",\"enabled\":1}",
            "{\"action\":\"pause\",\"minutes\":1.5}",
            "{\"action\":\"delete-everything\"}",
            "{\"action\":\"travel\"}"
        ] {
            #expect(throws: (any Error).self) {
                try BGJSON.decoder().decode(BGChargingActionRequest.self, from: Data(json.utf8))
            }
        }
        let request = BGChargingActionRequest(action: .travel, readyAt: now.addingTimeInterval(3600))
        #expect(try BGJSON.decoder().decode(BGChargingActionRequest.self, from: BGJSON.encoder().encode(request)) == request)
    }

    @MainActor @Test func uiAndAPIUseSameActionAndAPIRejectsUnsavedEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        let store = ConfigStore(configURL: url)
        let request = BGChargingActionRequest(action: .profile, profile: "mobile")
        let expected = try request.applying(to: BGConfig(), at: now)
        #expect(try store.performAPIAction(request, at: now) == expected)
        #expect(try BGConfigFile.read(at: url) == expected)
        #expect(!store.hasUnsavedChanges)
        store.config.upperLimit = 95
        #expect(throws: (any Error).self) { try store.performAPIAction(request, at: now) }
        #expect(store.config.upperLimit == 95)
        store.flushPendingSave()
        #expect(store.performAction(request, at: now))
        #expect(store.config == expected)
        store.flushPendingSave()
    }

    @MainActor @Test func failedAPISaveAndInvalidUIActionPreserveConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        let store = ConfigStore(configURL: url)
        let original = store.config
        #expect(!store.performAction(BGChargingActionRequest(action: .travel, readyAt: now), at: now))
        #expect(store.config == original && !store.hasUnsavedChanges)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) {
            try store.performAPIAction(BGChargingActionRequest(action: .profile, profile: "desk"), at: now)
        }
        #expect(store.config == original && !store.hasUnsavedChanges)
        let preview = ConfigStore(loadImmediately: false, persistenceEnabled: false)
        #expect(throws: (any Error).self) {
            try preview.performAPIAction(BGChargingActionRequest(action: .profile, profile: "desk"), at: now)
        }
        #expect(preview.config == BGConfig())
    }
}
