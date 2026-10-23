import Foundation
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct EffectivenessAndAutomationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func status(keys: [String] = ["CHTE"], state: BGChargeState = .holding,
                        percent: Int = 60, native: Int? = nil,
                        externalDisplay: Bool? = nil, lidClosed: Bool? = nil,
                        allowsDisconnect: Bool? = nil, effectiveUpper: Int? = nil) -> BGStatus {
        var s = BGStatus()
        s.smcKeysDetected = keys
        s.state = state
        s.percent = percent
        s.nativeChargeLimit = native
        s.externalDisplayConnected = externalDisplay
        s.lidClosed = lidClosed
        s.adapterDisconnectAllowed = allowsDisconnect
        s.effectiveUpperLimit = effectiveUpper
        s.daemonVersion = "0.6.0"
        s.updatedAt = now
        return s
    }

    @Test func desktopProfileChangesOnlyLimitsWhenAppropriate() {
        var config = BGConfig()
        config.desktopProfileEnabled = true
        config.desktopProfile = .everyday
        config.lowerLimit = 55
        config.upperLimit = 60

        let active = BGDesktopProfileRule.resolve(config: config, externalDisplay: true, now: now)
        #expect(active.active)
        #expect(active.config.lowerLimit == 75 && active.config.upperLimit == 80)

        #expect(!BGDesktopProfileRule.resolve(config: config, externalDisplay: false, now: now).active)

        var paused = config
        paused.pauseUntil = now.addingTimeInterval(600)
        #expect(!BGDesktopProfileRule.resolve(config: paused, externalDisplay: true, now: now).active)

        var manual = config
        manual.manualOverrideUntil = now.addingTimeInterval(600)
        #expect(!BGDesktopProfileRule.resolve(config: manual, externalDisplay: true, now: now).active)

        var planned = config
        planned.specialChargePlan = BGSpecialChargePlan(kind: .hold, targetPercent: 50,
                                                        createdAt: now, expiresAt: now.addingTimeInterval(3600))
        #expect(!BGDesktopProfileRule.resolve(config: planned, externalDisplay: true, now: now).active)

        var native = config
        native.mode = .native
        #expect(!BGDesktopProfileRule.resolve(config: native, externalDisplay: true, now: now).active)
    }

    @Test func effectivenessNamesTheActuallyAppliedRule() {
        var config = BGConfig()
        config.lowerLimit = 55
        config.upperLimit = 80

        let effective = BGEffectiveness.evaluate(config: config, status: status(effectiveUpper: 80),
                                                 daemonActive: true, daemonCurrent: true, now: now)
        #expect(effective.state == .effective)
        #expect(effective.controlPath == .chargeLock)
        #expect(effective.targetUpperLimit == 80 && effective.appliedUpperLimit == 80)

        let native = BGEffectiveness.evaluate(config: config, status: status(native: 60),
                                              daemonActive: true, daemonCurrent: true, now: now)
        #expect(native.state == .limitedByNative)

        var paused = config
        paused.pauseUntil = now.addingTimeInterval(600)
        #expect(BGEffectiveness.evaluate(config: paused, status: status(),
                                         daemonActive: true, daemonCurrent: true, now: now).state == .inactive)

        let fallback = BGEffectiveness.evaluate(config: config,
                                                status: status(state: .disabled, externalDisplay: true,
                                                               allowsDisconnect: false),
                                                daemonActive: true, daemonCurrent: true, now: now)
        #expect(fallback.state == .desktopFallback)

        let unsupported = BGEffectiveness.evaluate(config: config, status: status(keys: [], state: .unsupported),
                                                   daemonActive: true, daemonCurrent: true, now: now)
        #expect(unsupported.state == .unsupported)

        #expect(BGEffectiveness.evaluate(config: config, status: status(),
                                         daemonActive: false, daemonCurrent: true, now: now).state == .daemonInactive)
        #expect(BGEffectiveness.evaluate(config: config, status: status(),
                                         daemonActive: true, daemonCurrent: false, now: now).state == .daemonOutdated)

        var nativeMode = config
        nativeMode.mode = .native
        let observing = BGEffectiveness.evaluate(config: nativeMode, status: status(native: 70),
                                                 daemonActive: true, daemonCurrent: true, now: now)
        #expect(observing.state == .effective)
        #expect(observing.controlPath == .macOS)
        #expect(observing.targetUpperLimit == 70)
    }

    @Test func newConfigFieldsDecodeAndMerge() throws {
        let json = #"{"enabled":true,"lowerLimit":55,"upperLimit":60,"desktopProfileEnabled":true,"desktopProfile":"mobile","lowPowerModeOnBattery":true,"preventSleepWhileDischarging":true}"#
        let config = try BGJSON.decoder().decode(BGConfig.self, from: Data(json.utf8))
        #expect(config.desktopProfile == .mobile)
        #expect(config.lowPowerModeOnBattery)
        #expect(config.preventSleepWhileDischarging)

        let baseline = BGConfig()
        var edited = baseline
        edited.desktopProfileEnabled = true
        edited.desktopProfile = .everyday
        edited.lowPowerModeOnBattery = true
        var latest = baseline
        latest.upperLimit = 70
        let merged = edited.mergingEdits(since: baseline, into: latest)
        #expect(merged.desktopProfileEnabled && merged.desktopProfile == .everyday)
        #expect(merged.lowPowerModeOnBattery && merged.lowPowerModeRule == .onBattery)
        #expect(merged.upperLimit == 70)
    }

    @Test func capacityDaysCarryCyclesAndTemperatures() throws {
        let first = measurements(at: now, maximum: 4800, cycles: 100, temperature: 30)
        var days = BGCapacityTrend.recording(first, in: [], osVersion: "27.0", at: now)
        #expect(days.count == 1)
        #expect(days[0].cycleMean == 100)
        #expect(days[0].temperatureMaximum == 30)

        let later = now.addingTimeInterval(60)
        let second = measurements(at: later, maximum: 4900, cycles: 102, temperature: 33)
        days = BGCapacityTrend.recording(second, in: days, osVersion: "27.0", at: later)
        #expect(days[0].cycleSamples == 2)
        #expect(days[0].cycleMean == 101)
        #expect(days[0].temperatureMaximum == 33)

        let csv = BGCapacityTrend.csv(days)
        #expect(csv.hasPrefix("day_utc,capacity_percent"))
        #expect(csv.contains(",101.00,33.00,"))

        let encoded = try BGJSON.encoder().encode(days[0])
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "cycleSum")
        object.removeValue(forKey: "cycleSamples")
        object.removeValue(forKey: "temperatureMaximum")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try BGJSON.decoder().decode(BGCapacityDay.self, from: legacy)
        #expect(decoded.cycleMean == nil)
        #expect(decoded.temperatureMaximum == nil)
    }

    @Test func weeklyReportUsesOnlyTheLastSevenDays() {
        func sample(_ date: Date, percent: Int, cycles: Int?) -> BGHistorySample {
            var s = BGStatus()
            s.updatedAt = date
            s.percent = percent
            s.cycleCount = cycles
            s.temperatureCelsius = 41
            s.state = .holding
            s.pluggedIn = true
            return BGHistorySample(status: s)
        }
        let samples = [
            sample(now.addingTimeInterval(-10 * 86400), percent: 100, cycles: 5),
            sample(now.addingTimeInterval(-3600), percent: 100, cycles: 140),
            sample(now.addingTimeInterval(-3540), percent: 95, cycles: 141),
            sample(now.addingTimeInterval(-3480), percent: 85, cycles: 142),
        ]
        let report = BGHistory.weeklyReport(samples, now: now)
        #expect(report.sampleCount == 3)
        #expect(report.fullChargeDays == 1)
        #expect(report.highestCycleCount == 142)
        #expect(report.summary.hotSeconds == 120)
    }

    private func measurements(at date: Date, maximum: Double, cycles: Double, temperature: Double) -> BGBatteryMeasurements {
        let max = BGMeasurement(.fullChargeCapacity, value: maximum, source: .rawMaxCapacity, sampledAt: date)
        let design = BGMeasurement(.designCapacity, value: 5000, source: .designCapacity, sampledAt: date)
        return BGBatteryMeasurements(values: [
            max, design,
            BGBatteryMeasurements.capacityRatio(maximum: max, design: design),
            BGMeasurement(.cycleCount, value: cycles, source: .registryCycles, sampledAt: date),
            BGMeasurement(.batteryTemperature, value: temperature, source: .registryTemperature, sampledAt: date),
        ])
    }
}

struct LowPowerAndSleepTests {
    final class PowerModeRecorder {
        typealias Call = (source: PowerModeController.Source, level: PowerModeController.Level, usePowerMode: Bool)
        var applied: [Call] = []
        var succeeds = true
        var powerModeSupported = false
        var driver: PowerModeController.Driver {
            PowerModeController.Driver(supportsPowerMode: { self.powerModeSupported }, apply: { source, level, usePowerMode in
                self.applied.append((source, level, usePowerMode))
                return self.succeeds
            })
        }
        var levels: [String] { applied.map { "\($0.source.rawValue)=\($0.level.rawValue)" } }
    }

    @Test func lowPowerModeIsWrittenPerSourceOnlyWhenEnabled() {
        let recorder = PowerModeRecorder()
        let controller = PowerModeController(driver: recorder.driver)
        var config = BGConfig()
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        #expect(recorder.applied.isEmpty)

        config.lowPowerModeRule = .onBattery
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        #expect(recorder.levels == ["-b=1", "-c=0"])
        #expect(recorder.applied.allSatisfy { !$0.usePowerMode })

        config.lowPowerModeRule = .always
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        #expect(recorder.levels.suffix(2) == ["-b=1", "-c=1"])

        config.lowPowerModeRule = .off
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        #expect(recorder.levels.suffix(2) == ["-b=0", "-c=0"])
        #expect(recorder.applied.count == 6)
    }

    @Test func highPowerModeNeedsSupportAndYieldsToLowPowerMode() {
        var config = BGConfig()
        config.highPowerModeRule = .always
        #expect(PowerModeController.desiredLevels(config: config, highPowerSupported: false) == nil)
        #expect(PowerModeController.desiredLevels(config: config, highPowerSupported: true) == [.battery: .high, .adapter: .high])
        config.lowPowerModeRule = .onBattery
        #expect(PowerModeController.desiredLevels(config: config, highPowerSupported: true) == [.battery: .low, .adapter: .high])
        #expect(PowerModeController.desiredLevels(config: config, highPowerSupported: false) == [.battery: .low, .adapter: .automatic])

        let recorder = PowerModeRecorder()
        recorder.powerModeSupported = true
        let controller = PowerModeController(driver: recorder.driver)
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        #expect(recorder.levels == ["-b=1", "-c=2"])
        #expect(recorder.applied.allSatisfy { $0.usePowerMode })
        #expect(controller.highPowerModeSupported)
    }

    @Test func powerModeRetriesAfterFailureAndHonoursDryRun() {
        let recorder = PowerModeRecorder()
        recorder.succeeds = false
        let controller = PowerModeController(driver: recorder.driver)
        var config = BGConfig()
        config.lowPowerModeRule = .onBattery
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        controller.reconcile(config: config, dryRun: false, logger: { _ in })
        #expect(recorder.applied.count == 4)

        recorder.succeeds = true
        controller.reconcile(config: config, dryRun: true, logger: { _ in })
        #expect(recorder.applied.count == 4)
    }

    @Test func powerModeRulesMigrateFromLegacyFieldAndRejectUnknownValues() throws {
        let legacy = try BGJSON.decoder().decode(BGConfig.self, from: Data(#"{"lowPowerModeOnBattery":true}"#.utf8))
        #expect(legacy.lowPowerModeRule == .onBattery && legacy.highPowerModeRule == .off)
        let unknown = try BGJSON.decoder().decode(BGConfig.self,
            from: Data(#"{"lowPowerModeOnBattery":true,"lowPowerModeRule":"turbo","highPowerModeRule":"turbo"}"#.utf8))
        #expect(unknown.lowPowerModeRule == .off && unknown.highPowerModeRule == .off)
        #expect(!unknown.lowPowerModeOnBattery)

        var edited = BGConfig()
        edited.lowPowerModeRule = .always
        edited.highPowerModeRule = .onAdapter
        let roundTrip = try BGJSON.decoder().decode(BGConfig.self, from: BGJSON.encoder().encode(edited.sanitized()))
        #expect(roundTrip.lowPowerModeRule == .always && roundTrip.highPowerModeRule == .onAdapter)
        #expect(!roundTrip.lowPowerModeOnBattery)
        let merged = edited.mergingEdits(since: BGConfig(), into: BGConfig())
        #expect(merged.lowPowerModeRule == .always && merged.highPowerModeRule == .onAdapter)
    }

    final class SleepRecorder {
        var created: [Double] = []
        var released: [UInt32] = []
        var nextID: UInt32 = 1
        var driver: DischargeSleepGuard.Driver {
            DischargeSleepGuard.Driver(create: { timeout in
                self.created.append(timeout)
                defer { self.nextID += 1 }
                return self.nextID
            }, release: { self.released.append($0) })
        }
    }

    @Test func sleepAssertionExistsOnlyDuringActiveDischarge() {
        let recorder = SleepRecorder()
        let guardUnit = DischargeSleepGuard(driver: recorder.driver)
        var config = BGConfig()
        config.preventSleepWhileDischarging = true
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guardUnit.reconcile(config: config, state: .holding, now: now, dryRun: false)
        #expect(recorder.created.isEmpty)

        guardUnit.reconcile(config: config, state: .discharging, now: now, dryRun: false)
        guardUnit.reconcile(config: config, state: .discharging, now: now.addingTimeInterval(20), dryRun: false)
        #expect(recorder.created == [DischargeSleepGuard.maximumDuration])

        guardUnit.reconcile(config: config, state: .holding, now: now.addingTimeInterval(40), dryRun: false)
        #expect(recorder.released == [1])

        guardUnit.reconcile(config: config, state: .discharging, now: now.addingTimeInterval(60), dryRun: false)
        #expect(recorder.created.count == 2)

        config.preventSleepWhileDischarging = false
        guardUnit.reconcile(config: config, state: .discharging, now: now.addingTimeInterval(80), dryRun: false)
        #expect(recorder.released.count == 2)
    }
}
