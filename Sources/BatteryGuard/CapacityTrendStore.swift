import Foundation
import Darwin
import BatteryGuardShared

actor CapacityTrendRepository {
    let url: URL
    private var cached: [BGCapacityDay]?
    init(url: URL) { self.url = url }

    func load(now: Date = Date()) throws -> [BGCapacityDay] {
        if let cached { return cached }
        guard let data = try readBoundedData() else { cached = []; return [] }
        let days = try BGJSON.decoder().decode([BGCapacityDay].self, from: data)
        guard days.count <= 1464, days.allSatisfy(\.isValid), Set(days.map(\.id)).count == days.count else {
            // Do not destroy or silently reset a damaged existing file.
            throw CocoaError(.fileReadCorruptFile)
        }
        cached = days.filter { $0.day >= now.addingTimeInterval(-BGCapacityTrend.retention) && $0.day <= now }
        return cached ?? []
    }

    private func readBoundedData() throws -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 2_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: 2_000_001) ?? Data()
        guard data.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    func record(_ status: BGStatus, now: Date = Date()) throws -> [BGCapacityDay] {
        let previous = try load(now: now)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let next = BGCapacityTrend.recording(status.diagnosticMeasurements(at: now), in: previous,
                                             osVersion: osVersion, at: now)
        guard next != previous else { return previous }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try BGJSON.encoder().encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        cached = next
        return next
    }
}
