import Foundation
import Darwin

/// Root-only recovery never treats permission, locking, or filesystem errors as corrupt JSON.
public enum BGConfigRecovery {
    public static var backupURL: URL {
        URL(fileURLWithPath: BGPaths.directory).appendingPathComponent("config.backup.json")
    }

    public struct Result: Sendable, Equatable {
        public let recovered: Bool
        public let usedBackup: Bool
        public let quarantinePath: String?
        public var message: String? {
            guard recovered else { return nil }
            return "Beschädigte Einstellungen gesichert und "
                + (usedBackup ? "aus dem letzten gültigen Stand" : "mit Standardwerten")
                + " wiederhergestellt. Schutz bleibt deaktiviert; bitte Einstellungen prüfen."
        }
    }

    /// Call with the valid *previous* configuration while holding the configuration lock.
    public static func backup(config: BGConfig) throws {
        guard geteuid() == 0 else { throw POSIXError(.EPERM) }
        try writeBackup(config: config, at: backupURL, requireRoot: true)
    }

    public static func prepare(
        configURL: URL = URL(fileURLWithPath: BGPaths.config),
        backupURL: URL = BGConfigRecovery.backupURL
    ) throws -> Result {
        try prepare(configURL: configURL, backupURL: backupURL, requireRoot: true)
    }

    // Internal root-check override permits isolated temporary-file tests only.
    static func prepare(configURL: URL, backupURL: URL, requireRoot: Bool) throws -> Result {
        if requireRoot && geteuid() != 0 { throw POSIXError(.EPERM) }
        guard configURL.standardizedFileURL != backupURL.standardizedFileURL else { throw POSIXError(.EINVAL) }
        try validateDirectory(configURL.deletingLastPathComponent(), requireRoot: requireRoot)
        try validateDirectory(backupURL.deletingLastPathComponent(), requireRoot: requireRoot)
        let fd = open(configURL.path, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        try validateFile(fd, requireRoot: requireRoot)
        var acquired = false
        for _ in 0..<20 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
            guard errno == EWOULDBLOCK || errno == EINTR else { throw posixError() }
            usleep(10_000)
        }
        guard acquired else { throw POSIXError(.EBUSY) }
        defer { _ = flock(fd, LOCK_UN) }
        try validateFile(fd, requireRoot: requireRoot)
        let original = try file.read(upToCount: 262_145) ?? Data()
        guard original.count <= 262_144 else { throw POSIXError(.EFBIG) }
        do {
            let config = try BGJSON.decoder().decode(BGConfig.self, from: original).sanitized()
            try writeBackup(config: config, at: backupURL, requireRoot: requireRoot)
            return Result(recovered: false, usedBackup: false, quarantinePath: nil)
        } catch is DecodingError {
            // Only typed JSON decoding failure authorizes recovery.
        }

        var restored = BGConfig()
        var usedBackup = false
        do {
            restored = try readBackup(at: backupURL, requireRoot: requireRoot)
            usedBackup = true
        } catch let error as POSIXError where error.code == .ENOENT {
            // No backup yet: explicitly disabled defaults are the safe starting point.
        } catch is DecodingError {
            // A corrupt regular backup also cannot authorize active charging control.
        }
        restored.enabled = false
        restored.pauseUntil = nil
        restored.chargeToFullOnce = false
        restored.fullChargeUntil = nil
        restored.travelReadyAt = nil
        restored = restored.sanitized()
        let replacement = try BGJSON.encoder().encode(restored)
        let quarantine = configURL.deletingLastPathComponent()
            .appendingPathComponent("config.corrupt-\(UUID().uuidString).json")
        let quarantineFD = open(quarantine.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard quarantineFD >= 0 else { throw posixError() }
        let quarantined = FileHandle(fileDescriptor: quarantineFD, closeOnDealloc: true)
        defer { try? quarantined.close() }
        try quarantined.write(contentsOf: original)
        try quarantined.synchronize()
        guard fchmod(quarantineFD, 0o644) == 0 else { throw posixError() }
        // Preserve the inode and its held lock so already-open cooperative writers cannot
        // modify an orphan file after recovery. Original bytes are durable before this write.
        try file.seek(toOffset: 0)
        try file.write(contentsOf: replacement)
        try file.truncate(atOffset: UInt64(replacement.count))
        try file.synchronize()
        return Result(recovered: true, usedBackup: usedBackup, quarantinePath: quarantine.path)
    }

    private static func writeBackup(config: BGConfig, at url: URL, requireRoot: Bool) throws {
        try validateDirectory(url.deletingLastPathComponent(), requireRoot: requireRoot)
        // Refuse symlinks and unsafe existing backups rather than replacing them.
        let existing = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if existing >= 0 {
            defer { close(existing) }
            try validateFile(existing, requireRoot: requireRoot, backup: true)
        } else if errno != ENOENT { throw posixError() }
        let data = try BGJSON.encoder().encode(config.sanitized())
        try data.write(to: url, options: .atomic)
        guard chmod(url.path, 0o644) == 0 else { throw posixError() }
    }

    private static func readBackup(at url: URL, requireRoot: Bool) throws -> BGConfig {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        try validateFile(fd, requireRoot: requireRoot, backup: true)
        let data = try file.read(upToCount: 262_145) ?? Data()
        guard data.count <= 262_144 else { throw POSIXError(.EFBIG) }
        return try BGJSON.decoder().decode(BGConfig.self, from: data).sanitized()
    }

    private static func validateFile(_ fd: Int32, requireRoot: Bool, backup: Bool = false) throws {
        var attributes = stat()
        guard fstat(fd, &attributes) == 0 else { throw posixError() }
        guard attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_size <= 262_144,
              !requireRoot || attributes.st_uid == 0,
              !backup || attributes.st_mode & 0o022 == 0 else { throw POSIXError(.EINVAL) }
    }

    private static func validateDirectory(_ url: URL, requireRoot: Bool) throws {
        var attributes = stat()
        guard lstat(url.path, &attributes) == 0 else { throw posixError() }
        guard attributes.st_mode & S_IFMT == S_IFDIR,
              !requireRoot || (attributes.st_uid == 0 && attributes.st_mode & 0o022 == 0) else {
            throw POSIXError(.EPERM)
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
