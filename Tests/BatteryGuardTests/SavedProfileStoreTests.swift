import XCTest
import Foundation
@testable import BatteryGuard
import BatteryGuardShared

@MainActor
final class SavedProfileStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var testFileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testFileURL = tempDirectory.appendingPathComponent("profiles.json")
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - CRUD Tests

    func testCRUDLifecycle() throws {
        let store = SavedProfileStore(fileURL: testFileURL)
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertFalse(store.isCorrupt)

        // 1. Add
        let profile1 = try BGSavedProfile(
            name: "Büro Standard",
            lowerLimit: 40,
            upperLimit: 80,
            heatProtectionCelsius: 40,
            activeDischargeAboveUpper: false
        )
        try store.add(profile1)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.name, "Büro Standard")
        XCTAssertEqual(store.profiles.first?.id, profile1.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFileURL.path))

        // Verify persistence with a fresh store instance
        let store2 = SavedProfileStore(fileURL: testFileURL)
        XCTAssertEqual(store2.profiles.count, 1)
        XCTAssertEqual(store2.profiles.first?.name, "Büro Standard")
        XCTAssertEqual(store2.profiles.first?.id, profile1.id)

        // 2. Update (retain ID)
        let updatedProfile1 = try BGSavedProfile(
            id: profile1.id,
            name: "Büro Angepasst",
            lowerLimit: 50,
            upperLimit: 85,
            heatProtectionCelsius: 42,
            activeDischargeAboveUpper: true
        )
        try store.update(updatedProfile1)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.name, "Büro Angepasst")
        XCTAssertEqual(store.profiles.first?.lowerLimit, 50)
        XCTAssertEqual(store.profiles.first?.upperLimit, 85)
        XCTAssertEqual(store.profiles.first?.heatProtectionCelsius, 42)
        XCTAssertEqual(store.profiles.first?.activeDischargeAboveUpper, true)
        XCTAssertEqual(store.profiles.first?.id, profile1.id)

        // Verify reload sees updated data
        let store3 = SavedProfileStore(fileURL: testFileURL)
        XCTAssertEqual(store3.profiles.first?.name, "Büro Angepasst")
        XCTAssertEqual(store3.profiles.first?.activeDischargeAboveUpper, true)

        // 3. Delete
        try store.delete(id: profile1.id)
        XCTAssertTrue(store.profiles.isEmpty)

        // Verify persistence after deletion
        let store4 = SavedProfileStore(fileURL: testFileURL)
        XCTAssertTrue(store4.profiles.isEmpty)
    }

    func testSaveCurrentLimits() throws {
        let store = SavedProfileStore(fileURL: testFileURL)

        var config = BGConfig()
        config.lowerLimit = 35
        config.upperLimit = 75
        config.heatProtectionCelsius = 38
        config.activeDischargeAboveUpper = true

        let profile = try store.saveCurrentLimits(name: "Reise Profil", config: config)

        XCTAssertEqual(profile.name, "Reise Profil")
        XCTAssertEqual(profile.lowerLimit, 35)
        XCTAssertEqual(profile.upperLimit, 75)
        XCTAssertEqual(profile.heatProtectionCelsius, 38)
        XCTAssertTrue(profile.activeDischargeAboveUpper)
        XCTAssertEqual(store.profiles.count, 1)

        // Verify reload from disk
        let reloadStore = SavedProfileStore(fileURL: testFileURL)
        XCTAssertEqual(reloadStore.profiles.first?.name, "Reise Profil")
        XCTAssertEqual(reloadStore.profiles.first?.lowerLimit, 35)
    }

    // MARK: - Duplicate Prevention

    func testDuplicateNamePrevention() throws {
        let store = SavedProfileStore(fileURL: testFileURL)

        let profile1 = try BGSavedProfile(
            name: "Workstation",
            lowerLimit: 40,
            upperLimit: 80
        )
        try store.add(profile1)

        // Attempt adding case-insensitive duplicate
        let profile2 = try BGSavedProfile(
            name: "workstation",
            lowerLimit: 30,
            upperLimit: 70
        )

        XCTAssertThrowsError(try store.add(profile2)) { error in
            guard case BGSavedProfileError.duplicateProfileName(let name) = error else {
                XCTFail("Expected duplicateProfileName error, got: \(error)")
                return
            }
            XCTAssertEqual(name.lowercased(), "workstation")
        }

        // Memory state must remain untouched
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.id, profile1.id)
    }

    func testDuplicateIDPrevention() throws {
        let store = SavedProfileStore(fileURL: testFileURL)
        let sharedID = UUID()

        let profile1 = try BGSavedProfile(
            id: sharedID,
            name: "Profil A",
            lowerLimit: 40,
            upperLimit: 80
        )
        try store.add(profile1)

        let profile2 = try BGSavedProfile(
            id: sharedID,
            name: "Profil B",
            lowerLimit: 50,
            upperLimit: 90
        )

        XCTAssertThrowsError(try store.add(profile2)) { error in
            guard case BGSavedProfileError.duplicateProfileID(let id) = error else {
                XCTFail("Expected duplicateProfileID error, got: \(error)")
                return
            }
            XCTAssertEqual(id, sharedID)
        }

        XCTAssertEqual(store.profiles.count, 1)
    }

    // MARK: - Corrupt File Preservation & Explicit Replace

    func testCorruptFilePreservedAndNeverOverwrittenWithoutExplicitReplace() throws {
        let corruptPayload = "{ this is completely invalid JSON content 12345 }".data(using: .utf8)!
        try corruptPayload.write(to: testFileURL)

        // Initialize store pointing to corrupt file
        let store = SavedProfileStore(fileURL: testFileURL)

        XCTAssertTrue(store.isCorrupt)
        XCTAssertNotNil(store.loadErrorMessage)
        XCTAssertTrue(store.profiles.isEmpty)

        // Verify the original file on disk is strictly preserved byte-for-byte
        let diskBytesBefore = try Data(contentsOf: testFileURL)
        XCTAssertEqual(diskBytesBefore, corruptPayload)

        // Attempting to add a profile MUST throw and MUST NOT overwrite corrupt file
        let validProfile = try BGSavedProfile(
            name: "Neues Profil",
            lowerLimit: 40,
            upperLimit: 80
        )
        XCTAssertThrowsError(try store.add(validProfile)) { error in
            XCTAssertEqual(error as? SavedProfileStoreError, .corruptFilePreserved)
        }

        let diskBytesAfterAdd = try Data(contentsOf: testFileURL)
        XCTAssertEqual(diskBytesAfterAdd, corruptPayload, "Corrupt file on disk must not be overwritten by add")

        // Attempting to update or delete MUST also throw corruptFilePreserved
        XCTAssertThrowsError(try store.update(validProfile)) { error in
            XCTAssertEqual(error as? SavedProfileStoreError, .corruptFilePreserved)
        }
        XCTAssertThrowsError(try store.delete(id: validProfile.id)) { error in
            XCTAssertEqual(error as? SavedProfileStoreError, .corruptFilePreserved)
        }

        let diskBytesAfterMutations = try Data(contentsOf: testFileURL)
        XCTAssertEqual(diskBytesAfterMutations, corruptPayload, "Corrupt file on disk must still be preserved")

        // Explicit replace import should succeed and clear the corrupt state
        let collection = try BGSavedProfileCollection(profiles: [validProfile])
        try store.replaceCollection(collection)

        XCTAssertFalse(store.isCorrupt)
        XCTAssertNil(store.loadErrorMessage)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.name, "Neues Profil")

        // Disk now contains valid collection
        let reloadedStore = SavedProfileStore(fileURL: testFileURL)
        XCTAssertFalse(reloadedStore.isCorrupt)
        XCTAssertEqual(reloadedStore.profiles.count, 1)
        XCTAssertEqual(reloadedStore.profiles.first?.name, "Neues Profil")
    }

    // MARK: - Save Failure & Atomic Write Rollback

    func testSaveFailurePreservesMemoryState() throws {
        // Create an initial valid file with 1 profile
        let store = SavedProfileStore(fileURL: testFileURL)
        let initialProfile = try BGSavedProfile(
            name: "Initial Profile",
            lowerLimit: 40,
            upperLimit: 80
        )
        try store.add(initialProfile)
        XCTAssertEqual(store.profiles.count, 1)

        // Make destination path unwritable by replacing the file with an unwritable directory structure
        // Or changing permissions on parent directory
        let unwritableDir = tempDirectory.appendingPathComponent("unwritableDir")
        try FileManager.default.createDirectory(at: unwritableDir, withIntermediateDirectories: true)
        let targetFileInDir = unwritableDir.appendingPathComponent("profiles.json")

        // Create initial store
        let failingStore = SavedProfileStore(fileURL: targetFileInDir)
        let profileToPersist = try BGSavedProfile(
            name: "Existing Profile",
            lowerLimit: 40,
            upperLimit: 80
        )
        try failingStore.add(profileToPersist)
        XCTAssertEqual(failingStore.profiles.count, 1)

        // Remove write permissions from directory to force atomic write failure
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: unwritableDir.path)
        defer {
            // Restore write permissions in cleanup
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unwritableDir.path)
        }

        let newCandidate = try BGSavedProfile(
            name: "Candidate That Fails",
            lowerLimit: 30,
            upperLimit: 70
        )

        // Adding should throw saveFailed and memory state must NOT be updated
        XCTAssertThrowsError(try failingStore.add(newCandidate)) { error in
            guard case SavedProfileStoreError.saveFailed = error else {
                XCTFail("Expected saveFailed error, got: \(error)")
                return
            }
        }

        // Verify in-memory state remains exactly 1 profile
        XCTAssertEqual(failingStore.profiles.count, 1)
        XCTAssertEqual(failingStore.profiles.first?.name, "Existing Profile")
    }

    // MARK: - Bounded Read (<= 256 KiB before allocation)

    func testBoundedReadRejectsOversizedPayload() throws {
        // Create file larger than 256 KiB (256 * 1024 + 10 bytes)
        let oversizedSize = BGSavedProfileCollection.maxImportDataBytes + 10
        let oversizedData = Data(repeating: 0x20, count: oversizedSize) // spaces
        try oversizedData.write(to: testFileURL)

        let store = SavedProfileStore(fileURL: testFileURL)
        XCTAssertTrue(store.isCorrupt)
        XCTAssertNotNil(store.loadErrorMessage)

        // Verify original file on disk is preserved
        let diskSize = try FileManager.default.attributesOfItem(atPath: testFileURL.path)[.size] as? Int
        XCTAssertEqual(diskSize, oversizedSize)

        // Mutating must be rejected
        let candidate = try BGSavedProfile(name: "Test", lowerLimit: 40, upperLimit: 80)
        XCTAssertThrowsError(try store.add(candidate)) { error in
            XCTAssertEqual(error as? SavedProfileStoreError, .corruptFilePreserved)
        }
    }
}
