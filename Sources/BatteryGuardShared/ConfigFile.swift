import Foundation
import Darwin

/// Writers serialize on a separate, never-replaced lock file and replace the
/// configuration atomically (temporary file, F_FULLFSYNC, rename). Readers therefore
/// always see either the complete old or the complete new file, even after a crash,
/// power loss or a full disk.
public enum BGConfigFile {
    static let maximumSize = 262_144

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    /// Bounded non-blocking wait: a stalled writer must not freeze the UI or sleep acknowledgement.
    static func acquire(_ descriptor: Int32, _ operation: Int32) throws {
        for _ in 0..<20 {
            if flock(descriptor, operation | LOCK_NB) == 0 { return }
            guard errno == EWOULDBLOCK || errno == EINTR else { throw posixError() }
            usleep(10_000)
        }
        throw POSIXError(.EBUSY)
    }

    static func lockURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".lock")
    }

    /// Exclusive writer transaction. The lock file lives next to the configuration
    /// in the same root-owned directory and is never renamed, so every writer locks
    /// the same inode even though the configuration itself is replaced.
    static func withWriterLock<T>(for url: URL, operation: () throws -> T) throws -> T {
        let descriptor = open(lockURL(for: url).path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw posixError() }
        defer { _ = close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_uid == geteuid() else { throw POSIXError(.EINVAL) }
        try acquire(descriptor, LOCK_EX)
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    /// Writes `data` to a new temporary file in the same directory, flushes it to
    /// permanent storage and renames it over `url`. `rename(2)` is atomic and replaces
    /// a symlink instead of following it. On macOS `fsync(2)` does not flush the drive
    /// cache; `F_FULLFSYNC` does (see fsync(2) and fcntl(2)).
    static func replaceAtomically(_ data: Data, at url: URL, permissions: mode_t = 0o644) throws {
        guard data.count <= maximumSize else { throw POSIXError(.EFBIG) }
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw posixError() }
        var renamed = false
        defer {
            _ = close(descriptor)
            if !renamed { _ = unlink(temporary.path) }
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                offset += written
            }
        }
        guard fchmod(descriptor, permissions) == 0 else { throw posixError() }
        if fcntl(descriptor, F_FULLFSYNC) != 0 {
            // Some file systems do not support F_FULLFSYNC; fall back to fsync.
            guard fsync(descriptor) == 0 else { throw posixError() }
        }
        guard rename(temporary.path, url.path) == 0 else { throw posixError() }
        renamed = true
        let directoryDescriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            _ = close(directoryDescriptor)
        }
    }

    /// Reads one complete snapshot. A shared lock keeps compatibility with older
    /// daemons that still rewrote the file in place; it never contends with new writers.
    private static func readData(at url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_size <= maximumSize else { throw POSIXError(.EINVAL) }
        try acquire(descriptor, LOCK_SH)
        defer { _ = flock(descriptor, LOCK_UN) }
        let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        guard data.count <= maximumSize else { throw POSIXError(.EFBIG) }
        return data
    }

    private static func decode(at url: URL) throws -> BGConfig {
        try BGJSON.decoder().decode(BGConfig.self, from: readData(at: url)).sanitized()
    }

    public static func read(at url: URL) throws -> BGConfig {
        try decode(at: url)
    }

    /// Commands are applied under the service writer lock against current state.
    public static func performAction(_ request: BGChargingActionRequest, at url: URL, now: Date? = nil) throws -> BGConfig {
        if geteuid() != 0 && url.path == BGPaths.config {
            return try BGConfigClient.performAction(request)
        }
        return try update(at: url) { latest in
            latest = try request.applying(to: latest, at: now ?? Date())
        }
    }

    @discardableResult
    public static func update(at url: URL, mutation: (inout BGConfig) throws -> Void) throws -> BGConfig {
        if geteuid() != 0 && url.path == BGPaths.config {
            let baseline = try read(at: url)
            var desired = baseline
            try mutation(&desired)
            return try BGConfigClient.update(baseline: baseline, desired: desired)
        }
        return try withWriterLock(for: url) {
            var config = try decode(at: url)
            let previous = config
            try mutation(&config)
            config = config.sanitized()
            // Unveränderte Stände nicht neu schreiben: spart Schreibzugriffe und Backups.
            guard config != previous else { return config }
            let data = try BGJSON.encoder().encode(config)
            guard data.count <= maximumSize else { throw POSIXError(.EFBIG) }
            if geteuid() == 0 && url.path == BGPaths.config {
                try BGConfigRecovery.backup(config: previous)
            }
            try replaceAtomically(data, at: url)
            return config
        }
    }
}

public extension BGConfig {
    /// Apply only fields edited by this app; retain unrelated changes from the daemon.
    func mergingEdits(since baseline: BGConfig, into latest: BGConfig, now: Date = Date()) -> BGConfig {
        var result = latest
        if enabled != baseline.enabled { result.enabled = enabled }
        if lowerLimit != baseline.lowerLimit { result.lowerLimit = lowerLimit }
        if upperLimit != baseline.upperLimit { result.upperLimit = upperLimit }
        if activeDischargeAboveUpper != baseline.activeDischargeAboveUpper { result.activeDischargeAboveUpper = activeDischargeAboveUpper }
        if heatProtectionCelsius != baseline.heatProtectionCelsius { result.heatProtectionCelsius = heatProtectionCelsius }
        if magsafeLed != baseline.magsafeLed { result.magsafeLed = magsafeLed }
        if desktopProfileEnabled != baseline.desktopProfileEnabled { result.desktopProfileEnabled = desktopProfileEnabled }
        if desktopProfile != baseline.desktopProfile { result.desktopProfile = desktopProfile }
        if lowPowerModeOnBattery != baseline.lowPowerModeOnBattery { result.lowPowerModeOnBattery = lowPowerModeOnBattery }
        if preventSleepWhileDischarging != baseline.preventSleepWhileDischarging { result.preventSleepWhileDischarging = preventSleepWhileDischarging }
        if mode != baseline.mode { result.mode = mode }
        // Legacy edits get the same bounds as typed actions: pause ≤ 12 h,
        // travel within 30 days, full charge ≤ 8 h with a deadline.
        if pauseUntil != baseline.pauseUntil,
           pauseUntil.map({ $0.timeIntervalSince(now) <= 720 * 60 }) ?? true {
            result.pauseUntil = pauseUntil
        }
        if travelReadyAt != baseline.travelReadyAt || travelRequestID != baseline.travelRequestID,
           travelReadyAt.map({ $0 > now && $0.timeIntervalSince(now) <= 30 * 24 * 3600 }) ?? true {
            result.travelReadyAt = travelReadyAt
            result.travelRequestID = travelRequestID
        }
        // These fields are one logical request, so never merge them independently.
        let fullChargeBounded = !chargeToFullOnce
            || (fullChargeUntil.map { $0 > now && $0.timeIntervalSince(now) <= 8 * 3600 } ?? false)
        if chargeToFullOnce != baseline.chargeToFullOnce || fullChargeUntil != baseline.fullChargeUntil
            || fullChargeRequestID != baseline.fullChargeRequestID, fullChargeBounded {
            result.chargeToFullOnce = chargeToFullOnce
            result.fullChargeUntil = fullChargeUntil
            result.fullChargeRequestID = fullChargeRequestID
        }
        // Legacy field edits may cancel a known request, but may never create one.
        // Creation must pass typed service actions and hardware eligibility checks.
        if specialChargePlan == nil, let old = baseline.specialChargePlan,
           latest.specialChargePlan?.requestID == old.requestID { result.specialChargePlan = nil }
        if result.enabled == false || result.mode == .native || result.mode == .direct { result.specialChargePlan = nil }
        if lowerLimit != baseline.lowerLimit || upperLimit != baseline.upperLimit
            || enabled != baseline.enabled || mode != baseline.mode
            || heatProtectionCelsius != baseline.heatProtectionCelsius
            || activeDischargeAboveUpper != baseline.activeDischargeAboveUpper {
            result.manualOverrideUntil = now.addingTimeInterval(2 * 3600)
        }
        return result.sanitized()
    }
}
