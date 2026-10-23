import Testing
import Foundation
import BatteryGuardShared
@testable import BatteryGuard

struct Automation08Tests {
    let now = Date(timeIntervalSince1970: 1_800_000_000) // Freitag, 15.01.2027
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    @Test func templatesCreateEnabledTasksAtTheNextMatchingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let monday = try BGScheduleTemplate.mondayTopUp.tasks(now: now, timeZone: berlin)
        #expect(monday.count == 1 && monday[0].enabled && monday[0].action.kind == .topUp && monday[0].action.minutes == 240)
        #expect(calendar.component(.weekday, from: monday[0].schedule.startsAt) == 2)
        #expect(calendar.component(.hour, from: monday[0].schedule.startsAt) == 5)
        #expect(monday[0].schedule.startsAt > now && monday[0].schedule.recurrence == .weekly)
        let weekend = try BGScheduleTemplate.weekendFullCharge.tasks(now: now, timeZone: berlin)
        #expect(calendar.component(.weekday, from: weekend[0].schedule.startsAt) == 7 && weekend[0].action.minutes == 1440)
        let peak = try BGScheduleTemplate.peakHours.tasks(now: now, timeZone: berlin)
        #expect(peak.count == 2 && peak.allSatisfy { $0.schedule.recurrence == .weekdays })
        #expect(peak.map { $0.action.profile?.upperLimit } == [BGProfile.desk.upper, BGProfile.everyday.upper])
        // Jede Vorlage besteht die Validierung des Dienstes.
        for task in monday + weekend + peak { _ = try task.validated() }
    }

    @Test func clearScheduleHistoryKeepsTasksAndSetsNoOverride() throws {
        var config = BGConfig()
        config.scheduleHistory = [BGScheduleRun(taskID: UUID(), occurrenceAt: now, executedAt: now, resultString: "stored: requested action")]
        let next = try BGChargingActionRequest(action: .clearScheduleHistory).applying(to: config, at: now)
        #expect(next.scheduleHistory.isEmpty && next.manualOverrideUntil == nil)
    }

    @Test func urlCommandsMapToValidatedActions() throws {
        func request(_ text: String) throws -> BGChargingActionRequest { try BGURLCommand.request(for: URL(string: text)!) }
        #expect(try request("bguard://profile/desk").profile == "desk")
        let limit = try request("bguard://limit/60?lower=50")
        #expect(limit.action == .savedProfile && limit.savedProfile?.upperLimit == 60 && limit.savedProfile?.lowerLimit == 50)
        #expect(try request("bguard://limit/90").savedProfile?.lowerLimit == 85)
        #expect(try request("bguard://pause?minutes=30").minutes == 30)
        #expect(try request("bguard://pause").minutes == 60)
        #expect(try request("bguard://protection/off").enabled == false)
        #expect(try request("bguard://power-mode?low=onBattery").lowPowerMode == .onBattery)
        #expect(try request("bguard://led/off").magsafeLED == .off)
        #expect(try request("bguard://top-up").action == .topUp)
        for invalid in ["bguard://limit/10", "bguard://profile/turbo", "bguard://unknown", "https://limit/60",
                        "bguard://led/blink", "bguard://power-mode?low=turbo", "bguard://protection/maybe"] {
            #expect(throws: (any Error).self) { try request(invalid) }
        }
    }

    @Test func ledActionSetsTheModeWithoutOverride() throws {
        let next = try BGChargingActionRequest(action: .magsafeLED, magsafeLED: .off).applying(to: BGConfig(), at: now)
        #expect(next.magsafeLedMode == .off && next.magsafeLedOff && !next.magsafeLed && next.manualOverrideUntil == nil)
        #expect(throws: (any Error).self) {
            try BGJSON.decoder().decode(BGChargingActionRequest.self, from: Data(#"{"action":"magsafe-led"}"#.utf8))
        }
    }

    @Test func networkRulesApplyOnlyWhenJoiningAMatchingNetwork() {
        let rules = [BGNetworkRule(ssid: "Büro", profile: .desk), BGNetworkRule(ssid: "Café", profile: .mobile)]
        #expect(BGNetworkRules.profileToApply(previousSSID: nil, currentSSID: "Büro", rules: rules) == .desk)
        #expect(BGNetworkRules.profileToApply(previousSSID: "Büro", currentSSID: "Büro", rules: rules) == nil)
        #expect(BGNetworkRules.profileToApply(previousSSID: "Büro", currentSSID: "büro", rules: rules) == nil)
        #expect(BGNetworkRules.profileToApply(previousSSID: "Büro", currentSSID: nil, rules: rules) == nil)
        #expect(BGNetworkRules.decode(BGNetworkRules.encode(rules)) == rules)
        #expect(BGNetworkRules.decode(Data("kaputt".utf8)).isEmpty)
    }

    func sample(_ minutesAgo: Double, watts: Double, plugged: Bool = false) -> BGHistorySample {
        var status = BGStatus()
        status.updatedAt = now.addingTimeInterval(-minutesAgo * 60)
        status.percent = 50
        status.watts = watts
        status.pluggedIn = plugged
        status.state = plugged ? .holding : .onBattery
        return BGHistorySample(status: status)
    }

    @Test func runtimeUsesTheAverageOfTheWindow() {
        // 5000 mAh · 50 % · 12 V = 30 Wh; Ø 10 W → 180 min.
        let samples = (0..<10).map { sample(Double($0), watts: $0.isMultiple(of: 2) ? -8 : -12) }
        #expect(BGRuntimeEstimate.minutesRemaining(samples: samples, windowMinutes: 15, now: now, percent: 50,
                                                   maxCapacityMah: 5000, voltageMillivolts: 12_000) == 180)
        #expect(BGRuntimeEstimate.minutesRemaining(samples: Array(samples.prefix(3)), windowMinutes: 15, now: now, percent: 50,
                                                   maxCapacityMah: 5000, voltageMillivolts: 12_000) == nil)
        let plugged = (0..<10).map { sample(Double($0), watts: -10, plugged: true) }
        #expect(BGRuntimeEstimate.minutesRemaining(samples: plugged, windowMinutes: 15, now: now, percent: 50,
                                                   maxCapacityMah: 5000, voltageMillivolts: 12_000) == nil)
        #expect(BGRuntimeEstimate.minutesRemaining(samples: samples, windowMinutes: 5, now: now, percent: 50,
                                                   maxCapacityMah: nil, voltageMillivolts: 12_000) == nil)
    }

    @MainActor @Test func hotKeysToggleFromTheCurrentState() {
        var config = BGConfig()
        #expect(GlobalHotKeys.Command.togglePause.url(config: config, now: now).absoluteString == "bguard://pause?minutes=60")
        config.pauseUntil = now.addingTimeInterval(600)
        #expect(GlobalHotKeys.Command.togglePause.url(config: config, now: now).absoluteString == "bguard://resume")
        #expect(GlobalHotKeys.Command.toggleLowPower.url(config: config).absoluteString == "bguard://power-mode?low=always")
        config.lowPowerModeRule = .always
        #expect(GlobalHotKeys.Command.toggleLowPower.url(config: config).absoluteString == "bguard://power-mode?low=off")
        for command in GlobalHotKeys.Command.allCases {
            #expect((try? BGURLCommand.request(for: command.url(config: config, now: now))) != nil)
        }
    }

    @Test func menuStylesSetOnlyCardSwitches() {
        let defaults = UserDefaults(suiteName: "bg-style-\(UUID().uuidString)")!
        MenuWindowStyle.minimal.apply(to: defaults)
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showPowerFlow) && !defaults.bool(forKey: MenuBarAppearanceKeys.showHealth))
        MenuWindowStyle.powerUser.apply(to: defaults)
        #expect(defaults.bool(forKey: MenuBarAppearanceKeys.showHealth) && defaults.bool(forKey: MenuBarAppearanceKeys.showNextTask))
        #expect(defaults.object(forKey: MenuBarAppearanceKeys.menuCardOrder) == nil)
    }
}
