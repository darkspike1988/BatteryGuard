import Testing
import Foundation
import BatteryGuardShared
@testable import batteryguardd

struct SoCPowerMonitorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func plist(_ processor: [String: Any]) -> Data {
        var data = try! PropertyListSerialization.data(fromPropertyList: ["processor": processor, "is_delta": true],
                                                       format: .xml, options: 0)
        data.append(0) // powermetrics trennt Datensätze mit NUL
        return data
    }

    @Test func parsesMilliwattsAndSkipsInvalidValues() {
        let power = SoCPowerMonitor.parse(plist(["cpu_power": 543.2, "gpu_power": 21.8, "ane_power": 0.0]), sampledAt: now)
        #expect(power?.cpuWatts == 0.5432)
        #expect(power?.socWatts.map { abs($0 - 0.565) < 0.0001 } == true)
        #expect(SoCPowerMonitor.parse(plist(["cpu_power": -1, "gpu_power": "x"]), sampledAt: now) == nil)
        #expect(SoCPowerMonitor.parse(Data("garbage".utf8), sampledAt: now) == nil)
    }

    @Test func freshnessCoversTheSamplingInterval() {
        let power = BGSoCPower(sampledAt: now, cpuWatts: 1, gpuWatts: nil, aneWatts: nil)
        #expect(power.isFresh(at: now.addingTimeInterval(60)))
        #expect(!power.isFresh(at: now.addingTimeInterval(120)))
        #expect(BGSoCPower(sampledAt: now, cpuWatts: .nan, gpuWatts: 2000, aneWatts: nil).socWatts == nil)
    }

    @Test func refreshIsThrottledAndRunsInBackground() async throws {
        // Die Messung läuft im Hintergrund; der Zähler braucht deshalb eine Sperre (Thread Sanitizer).
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            var calls: Int { lock.withLock { value } }
            func increment() { lock.withLock { value += 1 } }
        }
        let counter = Counter()
        let data = plist(["cpu_power": 1000.0])
        let monitor = SoCPowerMonitor(measure: {
            counter.increment()
            return data
        })
        monitor.refreshIfDue(now: now)
        monitor.refreshIfDue(now: now.addingTimeInterval(5))
        for _ in 0..<50 where monitor.latest == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(monitor.latest?.cpuWatts == 1)
        #expect(counter.calls == 1)
        monitor.refreshIfDue(now: now.addingTimeInterval(31))
        for _ in 0..<50 where counter.calls < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(counter.calls == 2)
    }
}
