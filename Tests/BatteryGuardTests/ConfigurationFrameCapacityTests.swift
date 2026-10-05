import Foundation
import Testing
@testable import BatteryGuardShared

struct ConfigurationFrameCapacityTests {
    @Test func maximumLegitimateScheduleConfigurationFitsReadAndWriteFrames() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var config = BGConfig()
        for _ in 0..<50 {
            let profile = try BGSavedProfile(name: String(repeating: "🔋", count: 60), lowerLimit: 75, upperLimit: 80)
            let rule = try ScheduledRule(name: String(repeating: "🔋", count: 60), timeZoneIdentifier: "Europe/Berlin", startsAt: now, recurrence: .daily)
            config.scheduledTasks.append(BGScheduledTask(schedule: rule, enabled: true, action: .init(kind: .profile, profile: profile),
                state: .init(lastOccurrenceDate: now, lastResult: "stored: requested action", lastExecutionDate: now)))
        }
        for _ in 0..<100 {
            config.scheduleHistory.append(.init(taskID: UUID(), occurrenceAt: now, executedAt: now, resultString: "failed: action unavailable or invalid"))
        }
        #expect(try BGJSON.encoder().encode(config).count <= 262_144)
        #expect(try BGJSON.encoder().encode(BGConfigResponse(config: config)).count <= BGConfigWire.maximumBytes)
        #expect(try BGJSON.encoder().encode(BGConfigRequest(baseline: config, desired: config)).count <= BGConfigWire.maximumBytes)
    }
}
