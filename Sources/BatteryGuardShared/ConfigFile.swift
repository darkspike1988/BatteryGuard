import Foundation
import Darwin

/// Cooperative locking keeps app and daemon on the same inode in a root-owned directory.
/// This prevents partial reads and conflicting read/modify/write transactions.
public enum BGConfigFile {
    private static func withFile<T>(at url: URL, writing: Bool,
                                    operation: (FileHandle) throws -> T) throws -> T {
        let descriptor = open(url.path, (writing ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_size <= 262_144 else { throw POSIXError(.EINVAL) }
        let lockType = (writing ? LOCK_EX : LOCK_SH) | LOCK_NB
        var acquired = false
        // Bound the wait: a stalled writer must not freeze the UI or sleep acknowledgement.
        for _ in 0..<20 {
            if flock(descriptor, lockType) == 0 { acquired = true; break }
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            usleep(10_000)
        }
        guard acquired else { throw POSIXError(.EBUSY) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation(handle)
    }

    private static func decode(_ handle: FileHandle) throws -> BGConfig {
        try handle.seek(toOffset: 0)
        let data = try handle.read(upToCount: 262_145) ?? Data()
        guard data.count <= 262_144 else { throw POSIXError(.EFBIG) }
        return try BGJSON.decoder().decode(BGConfig.self, from: data).sanitized()
    }

    public static func read(at url: URL) throws -> BGConfig {
        try withFile(at: url, writing: false) { try decode($0) }
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
        return try withFile(at: url, writing: true) { handle in
            var config = try decode(handle)
            let previous = config
            try mutation(&config)
            config = config.sanitized()
            let data = try BGJSON.encoder().encode(config)
            if geteuid() == 0 && url.path == BGPaths.config {
                try BGConfigRecovery.backup(config: previous)
            }
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: data)
            try handle.truncate(atOffset: UInt64(data.count))
            try handle.synchronize()
            return config
        }
    }
}

public extension BGConfig {
    /// Apply only fields edited by this app; retain unrelated changes from the daemon.
    func mergingEdits(since baseline: BGConfig, into latest: BGConfig) -> BGConfig {
        var result = latest
        if enabled != baseline.enabled { result.enabled = enabled }
        if lowerLimit != baseline.lowerLimit { result.lowerLimit = lowerLimit }
        if upperLimit != baseline.upperLimit { result.upperLimit = upperLimit }
        if activeDischargeAboveUpper != baseline.activeDischargeAboveUpper { result.activeDischargeAboveUpper = activeDischargeAboveUpper }
        if heatProtectionCelsius != baseline.heatProtectionCelsius { result.heatProtectionCelsius = heatProtectionCelsius }
        if magsafeLed != baseline.magsafeLed { result.magsafeLed = magsafeLed }
        if mode != baseline.mode { result.mode = mode }
        if pauseUntil != baseline.pauseUntil { result.pauseUntil = pauseUntil }
        if travelReadyAt != baseline.travelReadyAt || travelRequestID != baseline.travelRequestID {
            result.travelReadyAt = travelReadyAt
            result.travelRequestID = travelRequestID
        }
        // These fields are one logical request, so never merge them independently.
        if chargeToFullOnce != baseline.chargeToFullOnce || fullChargeUntil != baseline.fullChargeUntil
            || fullChargeRequestID != baseline.fullChargeRequestID {
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
            result.manualOverrideUntil = Date().addingTimeInterval(2 * 3600)
        }
        return result.sanitized()
    }
}
