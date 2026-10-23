import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import BatteryGuardShared

/// Liest nach dem Aufwachen das Energieprotokoll von macOS (`pmset -g log`, ohne root lesbar)
/// und bewertet die letzte Schlafphase auf Akku.
@Observable
@MainActor
final class SleepReportStore {
    static let shared = SleepReportStore()
    static let notifyKey = "bg.notifySleepDrain"
    private static let lastNotifiedKey = "bg.lastSleepDrainNotifiedAt"
    /// powerd schreibt den Wake-Eintrag mit kurzer Verzögerung.
    private static let wakeDelay: Duration = .seconds(30)

    private(set) var report: BGSleepReport?
    private(set) var blockers: [BGSleepBlocker] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    func start() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: Self.wakeDelay)
                await SleepReportStore.shared.refresh(notify: true)
            }
        }
    }

    func refresh(notify: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let sessions = await Task.detached(priority: .utility) { SleepReportStore.readSessions() }.value
        report = BGSleepAnalysis.latestReport(from: sessions)
        guard notify, let report, report.unusual else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.notifyKey) as? Bool ?? true else { return }
        let last = defaults.object(forKey: Self.lastNotifiedKey) as? Date
        guard last.map({ report.session.start > $0 }) ?? true else { return }
        defaults.set(report.session.start, forKey: Self.lastNotifiedKey)
        NotificationManager.shared.notifySleepDrain(report)
    }

    func refreshBlockers() {
        blockers = BGSleepBlocker.relevant(Self.readBlockers())
    }

    nonisolated private static func readSessions() -> [BGSleepSession] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return BGSleepAnalysis.sessions(from: BGPowerLogParser.events(from: String(decoding: data, as: UTF8.self)))
    }

    private static func readBlockers() -> [BGSleepBlocker] {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let byProcess = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return byProcess.flatMap { pid, entries in
            entries.map { entry in
                let process = entry["Process Name"] as? String
                    ?? NSRunningApplication(processIdentifier: pid.int32Value)?.localizedName
                    ?? "PID \(pid.int32Value)"
                return BGSleepBlocker(pid: pid.int32Value, process: process,
                                      type: entry["AssertType"] as? String ?? "",
                                      name: entry["AssertName"] as? String ?? "")
            }
        }
    }
}
