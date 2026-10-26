import Testing
import Foundation
import BatteryGuardShared

struct ChargingInsightTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func status(percent: Int, plugged: Bool = true, charging: Bool = false,
                capability: BGChargeCapability? = nil, keys: [String] = ["CHTE"]) -> BGStatus {
        var s = BGStatus()
        s.percent = percent
        s.pluggedIn = plugged
        s.isChargingHardware = charging
        s.chargeCapability = capability
        s.smcKeysDetected = keys
        return s
    }

    static let firmwareLocked = BGChargeCapability(keys: [
        "CHTE": .placeholder, "CH0B": .blocked, "CH0C": .blocked,
        "CHIE": .writable, "CH0J": .blocked, "CH0I": .blocked,
    ])

    @Test func capabilityDistinguishesFirmwareLockFromMissingKeys() {
        let locked = Self.firmwareLocked
        #expect(!locked.chargeInhibitAvailable)
        #expect(locked.adapterSwitchAvailable)
        #expect(locked.chargeInhibitBlockedByFirmware)

        let old = BGChargeCapability(keys: ["CHIE": .writable])
        #expect(!old.chargeInhibitAvailable)
        #expect(!old.chargeInhibitBlockedByFirmware)

        let open = BGChargeCapability(keys: ["CH0B": .unknown])
        #expect(open.chargeInhibitAvailable)
    }

    @Test func capabilityDecodingToleratesUnknownStates() throws {
        let json = #"{"keys":{"CHTE":"quantum","CHIE":"writable"}}"#
        let decoded = try BGJSON.decoder().decode(BGChargeCapability.self, from: Data(json.utf8))
        #expect(decoded.keys["CHTE"] == .unknown)
        #expect(decoded.keys["CHIE"] == .writable)
    }

    @Test func statusWithoutNewFieldsStillDecodes() throws {
        let json = #"{"percent":50,"pluggedIn":true,"state":"holding","chargeCapability":7}"#
        let decoded = try BGJSON.decoder().decode(BGStatus.self, from: Data(json.utf8))
        #expect(decoded.percent == 50)
        #expect(decoded.chargeCapability == nil)
        #expect(decoded.adapterReconnectsLastHour == nil)
    }

    @Test func statusRoundTripsCapability() throws {
        var s = status(percent: 70, capability: Self.firmwareLocked)
        s.adapterReconnectsLastHour = 2
        let decoded = try BGJSON.decoder().decode(BGStatus.self, from: BGJSON.encoder().encode(s))
        #expect(decoded.chargeCapability == Self.firmwareLocked)
        #expect(decoded.adapterReconnectsLastHour == 2)
    }

    @Test func inactiveDaemonAndUnpluggedComeFirst() {
        let c = BGConfig()
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 60), daemonActive: false, now: now)
                == [.daemonInactive])
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 60, plugged: false),
                                              daemonActive: true, now: now) == [.notPluggedIn])
    }

    @Test func firmwareLockExplainsWhyMacOSHoldsTheLimit() {
        var c = BGConfig(); c.upperLimit = 60; c.lowerLimit = 50
        var s = status(percent: 79, charging: true, capability: Self.firmwareLocked, keys: ["CHTE", "CH0B", "CHIE"])
        s.nativeChargeLimit = 80
        let reasons = BGChargingExplanation.reasons(config: c, status: s, daemonActive: true, now: now)
        #expect(reasons == [.firmwareBlocksChargeInhibit, .macOSHoldsLimit(nativeLimit: 80, target: 60)])
    }

    @Test func fullChargeAboveNativeLimitIsExplainedAsCalibration() {
        var c = BGConfig(); c.upperLimit = 80
        var s = status(percent: 100, capability: BGChargeCapability(keys: ["CHIE": .writable]), keys: ["CHIE"])
        s.nativeChargeLimit = 80
        let reasons = BGChargingExplanation.reasons(config: c, status: s, daemonActive: true, now: now)
        #expect(reasons.contains(.likelyMacOSCalibration(percent: 100, limit: 80)))
        #expect(!reasons.contains(.firmwareBlocksChargeInhibit))
    }

    @Test func withChargeInhibitReasonsFollowTheLimits() {
        var c = BGConfig(); c.upperLimit = 80; c.lowerLimit = 70
        let open = BGChargeCapability(keys: ["CHTE": .writable])
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 80, capability: open),
                                              daemonActive: true, now: now) == [.holdingAtLimit(upper: 80)])
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 60, charging: true, capability: open),
                                              daemonActive: true, now: now) == [.belowLowerLimit(lower: 70, upper: 80)])
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 75, charging: true, capability: open),
                                              daemonActive: true, now: now) == [.chargingTowardsLimit(upper: 80)])
    }

    @Test func pauseTravelAndProtectionOffAreNamed() {
        var c = BGConfig(); c.pauseUntil = now.addingTimeInterval(600)
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 90), daemonActive: true, now: now)
                == [.paused(until: now.addingTimeInterval(600))])
        c = BGConfig(); c.enabled = false
        #expect(BGChargingExplanation.reasons(config: c, status: status(percent: 90), daemonActive: true, now: now)
                == [.protectionOff])
        c = BGConfig(); c.travelReadyAt = now.addingTimeInterval(3600)
        let reasons = BGChargingExplanation.reasons(config: c, status: status(percent: 85, charging: true),
                                                    daemonActive: true, now: now)
        #expect(reasons.first == .travelCharging(readyAt: now.addingTimeInterval(3600)))
    }

    @Test func flappingAdapterIsReportedEvenWhenUnplugged() {
        var s = status(percent: 50, plugged: false)
        s.adapterReconnectsLastHour = 4
        #expect(BGChargingExplanation.reasons(config: BGConfig(), status: s, daemonActive: true, now: now)
                == [.adapterFlapping(count: 4), .notPluggedIn])
    }

    @Test func flapCounterIgnoresSelfInitiatedDisconnectsAndExpires() {
        var counter = BGAdapterFlapCounter()
        var t = now
        #expect(counter.observe(pluggedIn: true, selfInitiated: false, at: t) == 0)
        for _ in 0..<3 {
            t += 60; _ = counter.observe(pluggedIn: false, selfInitiated: false, at: t)
            t += 60; _ = counter.observe(pluggedIn: true, selfInitiated: false, at: t)
        }
        #expect(counter.observe(pluggedIn: true, selfInitiated: false, at: t) == 3)
        t += 60; _ = counter.observe(pluggedIn: false, selfInitiated: true, at: t)
        t += 60
        #expect(counter.observe(pluggedIn: true, selfInitiated: true, at: t) == 3)
        #expect(counter.observe(pluggedIn: true, selfInitiated: false, at: t + 3700) == 0)
    }
}

struct ChargingInsightSystemLimitTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func systemLimitModeExplainsTheLimitBGuardSets() {
        var config = BGConfig(); config.mode = .systemLimit; config.upperLimit = 60; config.lowerLimit = 55
        var s = BGStatus()
        s.percent = 60; s.pluggedIn = true
        s.chargeCapability = BGChargeCapability(keys: ["CHTE": .placeholder, "CHIE": .writable])
        s.systemChargeLimits = [80, 85, 90, 95, 100]
        s.systemChargeLimit = 60
        #expect(BGChargingExplanation.reasons(config: config, status: s, daemonActive: true, now: now)
                == [.holdingAtLimit(upper: 60), .bGuardSetsMacOSLimit(limit: 60)])
    }

    @Test func autoModeOffersTheMacOSLimitAndKnownCalibrationWins() {
        var s = BGStatus()
        s.percent = 100; s.pluggedIn = true
        s.chargeCapability = BGChargeCapability(keys: ["CHTE": .placeholder, "CHIE": .writable])
        s.systemChargeLimits = [80, 85, 90, 95, 100]
        s.nativeChargeLimit = 80
        var reasons = BGChargingExplanation.reasons(config: BGConfig(), status: s, daemonActive: true, now: now)
        #expect(reasons.contains(.canControlMacOSLimit))
        #expect(reasons.contains(.likelyMacOSCalibration(percent: 100, limit: 80)))
        s.appleCalibrationActive = true
        reasons = BGChargingExplanation.reasons(config: BGConfig(), status: s, daemonActive: true, now: now)
        #expect(reasons.first == .macOSCalibrating)
        #expect(!reasons.contains(.likelyMacOSCalibration(percent: 100, limit: 80)))
    }
}
