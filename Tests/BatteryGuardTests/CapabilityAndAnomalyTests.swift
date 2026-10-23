import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct CapabilityAndAnomalyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func capabilities(firmware: String = "20457.1.29", keys: [String] = ["CHIE", "ACLC"],
                      limits: [Int] = [80, 85, 90, 95, 100]) -> BGCapabilities {
        BGCapabilities(smcKeys: keys, firmwareVersion: firmware, macOSVersion: "27.0.0",
                       systemChargeLimits: limits, highPowerMode: false)
    }

    @Test func firmwareIsParsedFromTheDeviceTreeString() {
        #expect(PlatformInfo.parseFirmware(Data("mBoot-20457.1.29\0\0".utf8)) == "20457.1.29")
        #expect(PlatformInfo.parseFirmware(Data("iBoot-11881.1.1".utf8)) == "11881.1.1")
        #expect(PlatformInfo.parseFirmware(Data()) == nil)
    }

    @Test func capabilitiesSortKeysAndDescribeChanges() {
        let old = capabilities(firmware: "11881.1.1", keys: ["CH0C", "CH0B", "CHIE", "ACLC"], limits: [])
        let new = capabilities()
        #expect(old.chargeLockKeys == ["CH0B", "CH0C"] && old.magSafeLED)
        #expect(new.changes(since: old) == ["Firmware 11881.1.1 → 20457.1.29", "SMC-Ladesperre nicht mehr verfügbar", "macOS-Limit verfügbar"])
        #expect(new.changes(since: new).isEmpty)
    }

    @Test func recordingReportsChangesOnlyAfterTheFirstRun() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bg-cap-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(PlatformInfo.recordCapabilities(capabilities(firmware: "1"), path: path, now: now) == nil)
        #expect(PlatformInfo.recordCapabilities(capabilities(firmware: "1"), path: path, now: now) == nil)
        let change = PlatformInfo.recordCapabilities(capabilities(firmware: "2"), path: path, now: now)
        #expect(change?.changes == ["Firmware 1 → 2"] && change?.detectedAt == now)
    }

    func status(percent: Int, limit: Int? = 80, plugged: Bool = true) -> BGStatus {
        var status = BGStatus()
        status.percent = percent
        status.pluggedIn = plugged
        status.effectiveUpperLimit = limit
        status.state = .holding
        return status
    }

    @Test func overLimitNeedsMarginAndActiveControl() {
        let config = BGConfig()
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 82), config: config, inputWatts: 20, batteryWatts: 0, now: now).isEmpty)
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 90), config: config, inputWatts: 20, batteryWatts: 0, now: now)
                == [.overLimit(percent: 90, limit: 80)])
        var native = config; native.mode = .native
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 90), config: native, inputWatts: 20, batteryWatts: 0, now: now).isEmpty)
        var full = config; full.chargeToFullOnce = true; full.fullChargeUntil = now.addingTimeInterval(3600)
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 90), config: full, inputWatts: 20, batteryWatts: 0, now: now).isEmpty)
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 90, plugged: false), config: config, inputWatts: 0, batteryWatts: -5, now: now).isEmpty)
    }

    @Test func appleCalibrationReplacesOverLimit() {
        var calibrating = status(percent: 95)
        calibrating.appleCalibrationActive = true
        #expect(BGChargeAnomaly.evaluate(status: calibrating, config: BGConfig(), inputWatts: 30, batteryWatts: 10, now: now)
                == [.appleCalibration])
    }

    @Test func missingExternalPowerOnlyBelowTargetAndNotDuringOwnDischarge() {
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 60), config: BGConfig(), inputWatts: 0.2, batteryWatts: -8, now: now)
                == [.externalPowerMissing])
        // Über dem Ziel entlädt die Firmware selbst: kein Alarm.
        #expect(BGChargeAnomaly.evaluate(status: status(percent: 81), config: BGConfig(), inputWatts: 0.2, batteryWatts: -8, now: now).isEmpty)
        var discharging = status(percent: 60); discharging.state = .discharging
        #expect(BGChargeAnomaly.evaluate(status: discharging, config: BGConfig(), inputWatts: 0.2, batteryWatts: -8, now: now).isEmpty)
    }
}
