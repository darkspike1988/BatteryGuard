import Testing
import Foundation
import BatteryGuardShared

struct SleepReportTests {
    static let sample = """
    2026-10-22 22:50:00 +0200 Assertions          \tPID 123(Safari) Created PreventUserIdleSystemSleep "Playing audio"
    2026-10-22 23:00:00 +0200 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:80%) 2 secs
    2026-10-23 01:00:00 +0200 DarkWake            \tDarkWake from Deep Idle [CDN] : due to EC.ARPT/Maintenance Using BATT (Charge:79%) 45 secs
    2026-10-23 01:01:00 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using BATT (Charge:79%) 3 secs
    2026-10-23 03:00:00 +0200 DarkWake            \tDarkWake from Deep Idle [CDN] : due to EC.ARPT/Maintenance Using BATT (Charge:78%) 30 secs
    2026-10-23 04:00:00 +0200 DarkWake            \tDarkWake from Deep Idle [CDN] : due to RTC/SleepService Using BATT (Charge:77%) 30 secs
    2026-10-23 07:00:00 +0200 Wake                \tWake from Deep Idle [CDNVA] : due to EC.LidOpen/Lid Open Using BATT (Charge:76%)
    garbage line
    """

    @Test func parsesSleepWakeAndDarkWakeLines() {
        let events = BGPowerLogParser.events(from: Self.sample)
        #expect(events.count == 6)
        #expect(events.first?.kind == .sleep)
        #expect(events.first?.reason == "Clamshell Sleep")
        #expect(events.first?.chargePercent == 80)
        #expect(events.first?.onAC == false)
        #expect(events[1].reason == "EC.ARPT/Maintenance")
        #expect(events.last?.kind == .wake)
        #expect(events.last?.reason == "EC.LidOpen/Lid Open")
    }

    @Test func buildsOneSessionWithDarkWakeReasons() throws {
        let sessions = BGSleepAnalysis.sessions(from: BGPowerLogParser.events(from: Self.sample))
        #expect(sessions.count == 1)
        let s = try #require(sessions.first)
        #expect(s.duration == 8 * 3600)
        #expect(s.drainPoints == 4)
        #expect(s.darkWakes == 3)
        #expect(s.darkWakeReasons.first == BGReasonCount(reason: "EC.ARPT/Maintenance", count: 2))
        #expect(abs(s.drainPerHour - 0.5) < 0.0001)
    }

    @Test func sessionsOnPowerAdapterOrTooShortAreIgnored() {
        let log = """
        2026-10-22 23:00:00 +0200 Sleep               \tEntering Sleep state due to 'Idle Sleep' Using AC (Charge:80%)
        2026-10-23 07:00:00 +0200 Wake                \tWake from Deep Idle [CDNVA] : due to EC.LidOpen Using AC (Charge:80%)
        2026-10-23 08:00:00 +0200 Sleep               \tEntering Sleep state due to 'Idle Sleep' Using Batt (Charge:80%)
        2026-10-23 08:10:00 +0200 Wake                \tWake from Deep Idle [CDNVA] : due to EC.LidOpen Using BATT (Charge:80%)
        2026-10-23 09:00:00 +0200 Sleep               \tEntering Sleep state due to 'Idle Sleep' Using Batt (Charge:80%)
        2026-10-23 12:00:00 +0200 Wake                \tWake from Deep Idle [CDNVA] : due to EC.LidOpen Using AC (Charge:82%)
        """
        #expect(BGSleepAnalysis.sessions(from: BGPowerLogParser.events(from: log)).isEmpty)
    }

    func session(hours: Double, drain: Int, at offset: Double) -> BGSleepSession {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + offset * 86400)
        return BGSleepSession(start: start, end: start.addingTimeInterval(hours * 3600), startPercent: 80,
                              endPercent: 80 - drain, darkWakes: 0, darkWakeReasons: [], wakeReason: nil)
    }

    @Test func unusualDrainIsComparedToTheUsualNight() throws {
        let usual = (0..<5).map { session(hours: 8, drain: 2, at: Double($0)) }
        let normal = try #require(BGSleepAnalysis.latestReport(from: usual + [session(hours: 8, drain: 3, at: 6)]))
        #expect(!normal.unusual)
        #expect(normal.baselinePerHour == 0.25)

        let heavy = try #require(BGSleepAnalysis.latestReport(from: usual + [session(hours: 8, drain: 12, at: 6)]))
        #expect(heavy.unusual)
    }

    @Test func withoutBaselineOnlyClearlyHighDrainIsUnusual() throws {
        #expect(try #require(BGSleepAnalysis.latestReport(from: [session(hours: 8, drain: 5, at: 0)])).unusual == false)
        #expect(try #require(BGSleepAnalysis.latestReport(from: [session(hours: 4, drain: 6, at: 0)])).unusual)
        #expect(BGSleepAnalysis.latestReport(from: []) == nil)
    }

    @Test func blockersKeepOnlySleepPreventingAssertions() {
        let all = [
            BGSleepBlocker(pid: 2, process: "Safari", type: "PreventUserIdleSystemSleep", name: "Playing audio"),
            BGSleepBlocker(pid: 2, process: "Safari", type: "PreventUserIdleDisplaySleep", name: "Playing audio"),
            BGSleepBlocker(pid: 3, process: "backupd", type: "PreventSystemSleep", name: "Backup"),
            BGSleepBlocker(pid: 3, process: "backupd", type: "NoIdleSleepAssertion", name: "Backup"),
        ]
        let relevant = BGSleepBlocker.relevant(all)
        #expect(relevant.map(\.process) == ["backupd", "Safari"])
    }
}
