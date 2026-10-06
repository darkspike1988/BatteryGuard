import Foundation
import Darwin
import Observation
import BatteryGuardShared

/// Error types thrown during profile store operations.
public enum SavedProfileStoreError: LocalizedError, Equatable, Sendable {
    case fileChanged
    case corruptFilePreserved
    case profileNotFound(UUID)
    case saveFailed(String)
    case payloadTooLarge(bytes: Int, maxBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .fileChanged:
            return "Die Profile wurden zwischenzeitlich geändert. Bitte Profile neu laden und die Änderung erneut durchführen."
        case .corruptFilePreserved:
            return "Die Profildatei ist beschädigt und wurde zum Schutz nicht überschrieben. Bitte reparieren oder durch einen Import ersetzen."
        case .profileNotFound(let id):
            return "Profil mit der ID \(id) wurde nicht gefunden."
        case .saveFailed(let message):
            return "Speichern der Profile fehlgeschlagen: \(message)"
        case .payloadTooLarge(let bytes, let maxBytes):
            return "Dateigröße (\(bytes) Bytes) überschreitet das Maximum von \(maxBytes) Bytes (256 KiB)."
        }
    }
}

/// Thread-safe, observable store managing persistent user-defined charging profiles.
///
/// Enforces:
/// - Atomic writes to disk before memory state mutation.
/// - Preservation of original files on load corruption (no overwriting without explicit replace/import).
/// - Strict size bounds (<= 256 KiB) verified before allocation.
@Observable
@MainActor
public final class SavedProfileStore: Sendable {
    public static let maxFileSizeBytes: Int = BGSavedProfileCollection.maxImportDataBytes // 256 KiB

    /// Default storage location in Application Support.
    public static var defaultProfilesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("BGuard", isDirectory: true).appendingPathComponent("profiles.json")
    }

    @ObservationIgnored private var diskSnapshot: Data?
    @ObservationIgnored private var hasLoaded = false

    public let fileURL: URL
    public private(set) var profiles: [BGSavedProfile] = []
    public private(set) var isCorrupt: Bool = false
    public private(set) var loadErrorMessage: String? = nil

    public init(fileURL: URL = SavedProfileStore.defaultProfilesURL, loadImmediately: Bool = true) {
        self.fileURL = fileURL
        if loadImmediately {
            _ = try? load()
        }
    }

    // MARK: - Bounded Disk Read

    /// Reads data from a file URL enforcing a strict size bound (<= 256 KiB) before reading and memory allocation.
    public static func readBoundedData(from url: URL) throws -> Data {
        let maxBytes = maxFileSizeBytes

        // Check file size attributes before allocating memory buffer
        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = resourceValues.fileSize {
            if fileSize > maxBytes {
                throw BGSavedProfileError.payloadTooLarge(bytes: fileSize, maxBytes: maxBytes)
            }
        } else {
            let path = url.path
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let sizeNum = attrs[.size] as? NSNumber {
                let fileSize = sizeNum.intValue
                if fileSize > maxBytes {
                    throw BGSavedProfileError.payloadTooLarge(bytes: fileSize, maxBytes: maxBytes)
                }
            }
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Bounded read up to 256 KiB + 1 byte
        guard let data = try handle.read(upToCount: maxBytes + 1) else {
            return Data()
        }
        if data.count > maxBytes {
            throw BGSavedProfileError.payloadTooLarge(bytes: data.count, maxBytes: maxBytes)
        }
        return data
    }

    // MARK: - Load & Corruption Protection

    /// Loads profiles from the configured fileURL.
    ///
    /// If the file is corrupt, marks `isCorrupt = true`, preserves the original file on disk,
    /// and prevents any subsequent mutations from overwriting it until an explicit replace import is performed.
    @discardableResult
    public func load() throws -> [BGSavedProfile] {
        var didRead = false
        do {
            let data = try currentDiskData()
            didRead = true
            diskSnapshot = data
            hasLoaded = true
            do {
                let loaded = try data.map { try BGSavedProfileCollection.importData($0).profiles } ?? []
                profiles = loaded
                isCorrupt = false
                loadErrorMessage = nil
                return loaded
            } catch {
                isCorrupt = true
                loadErrorMessage = error.localizedDescription
                throw error
            }
        } catch {
            if !didRead { isCorrupt = false }
            if case BGSavedProfileError.payloadTooLarge = error {
                isCorrupt = true
                hasLoaded = true
            }
            loadErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func currentDiskData() throws -> Data? {
        do { return try Self.readBoundedData(from: fileURL) }
        catch {
            let ns = error as NSError
            if (ns.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(ns.code))
                || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)) { return nil }
            throw error
        }
    }

    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        let directory = fileURL.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw SavedProfileStoreError.saveFailed(error.localizedDescription) }
        let fd = open(fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SavedProfileStoreError.saveFailed(String(cString: strerror(errno))) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw SavedProfileStoreError.saveFailed("Die Profilsperre ist keine reguläre Datei.")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            throw SavedProfileStoreError.saveFailed("Die Profile werden gerade verwendet. Bitte erneut versuchen.")
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private func ensureLoaded() throws {
        if !hasLoaded { try load() }
        if let message = loadErrorMessage, !isCorrupt {
            throw SavedProfileStoreError.saveFailed(message)
        }
    }

    // MARK: - Atomic Persistence

    /// Atomically serializes and writes the profile collection to disk.
    private func writeAtomically(collection: BGSavedProfileCollection) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw SavedProfileStoreError.saveFailed("Verzeichnis konnte nicht erstellt werden: \(error.localizedDescription)")
            }
        }

        let data = try collection.exportData()
        do {
            let current = try currentDiskData()
            guard current == diskSnapshot else { throw SavedProfileStoreError.fileChanged }
            try data.write(to: fileURL, options: .atomic)
            diskSnapshot = data
        } catch let error as SavedProfileStoreError { throw error }
        catch { throw SavedProfileStoreError.saveFailed(error.localizedDescription) }
    }

    // MARK: - CRUD Operations (Atomic write before memory state)

    /// Adds a new validated profile.
    ///
    /// Writes atomically to disk first; mutates memory state only upon successful write.
    public func add(_ profile: BGSavedProfile) throws {
        try ensureLoaded()
        try withFileLock {
            guard !isCorrupt else { throw SavedProfileStoreError.corruptFilePreserved }

            var candidate = profiles
            candidate.append(profile)

            // Validates collection (duplicate IDs, duplicate case-insensitive names, max count)
            let collection = try BGSavedProfileCollection(profiles: candidate)

            // Atomic write before memory mutation
            try writeAtomically(collection: collection)
            self.profiles = candidate


        }
    }

    /// Updates an existing profile while retaining its ID.
    ///
    /// Writes atomically to disk first; mutates memory state only upon successful write.
    public func update(_ profile: BGSavedProfile) throws {
        try ensureLoaded()
        try withFileLock {
            guard !isCorrupt else { throw SavedProfileStoreError.corruptFilePreserved }

            guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
                throw SavedProfileStoreError.profileNotFound(profile.id)
            }

            var candidate = profiles
            candidate[index] = profile

            let collection = try BGSavedProfileCollection(profiles: candidate)
            try writeAtomically(collection: collection)
            self.profiles = candidate


        }
    }

    /// Deletes a profile by its unique identifier.
    ///
    /// Writes atomically to disk first; mutates memory state only upon successful write.
    public func delete(id: UUID) throws {
        try ensureLoaded()
        try withFileLock {
            guard !isCorrupt else { throw SavedProfileStoreError.corruptFilePreserved }

            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                throw SavedProfileStoreError.profileNotFound(id)
            }

            var candidate = profiles
            candidate.remove(at: index)

            let collection = try BGSavedProfileCollection(profiles: candidate)
            try writeAtomically(collection: collection)
            self.profiles = candidate


        }
    }

    /// Creates and saves a new profile directly from the current active limits in `BGConfig`.
    @discardableResult
    public func saveCurrentLimits(name: String, config: BGConfig) throws -> BGSavedProfile {
        let profile = try BGSavedProfile(
            name: name,
            lowerLimit: config.lowerLimit,
            upperLimit: config.upperLimit,
            heatProtectionCelsius: config.heatProtectionCelsius,
            activeDischargeAboveUpper: config.activeDischargeAboveUpper
        )
        try add(profile)
        return profile
    }

    /// Explicitly replaces the entire profile collection with an imported one.
    ///
    /// This is the only operation permitted when the store is in a corrupt load state.
    public func replaceCollection(_ collection: BGSavedProfileCollection) throws {
        try ensureLoaded()
        try withFileLock {
            let current = try currentDiskData()
            guard current == diskSnapshot else { throw SavedProfileStoreError.fileChanged }
            if let current {
                let backup = fileURL.appendingPathExtension("backup-" + UUID().uuidString)
                try current.write(to: backup, options: .withoutOverwriting)
            }
            try writeAtomically(collection: collection)
            profiles = collection.profiles
            isCorrupt = false
            loadErrorMessage = nil
        }
    }

    /// Exports the current profiles as validated UTF-8 JSON data without any sensitive tokens.
    public func exportData() throws -> Data {
        try ensureLoaded()
        guard !isCorrupt else { throw SavedProfileStoreError.corruptFilePreserved }
        let collection = try BGSavedProfileCollection(profiles: profiles)
        return try collection.exportData()
    }
}
