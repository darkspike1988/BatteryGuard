import XCTest
@testable import BatteryGuardShared

final class SavedProfileTests: XCTestCase {

    // MARK: - Validation & Explicit Initializer Tests

    func testProfileValidationSuccess() throws {
        let profile = try BGSavedProfile(
            name: "  Night Profile  ",
            lowerLimit: 20,
            upperLimit: 80,
            heatProtectionCelsius: 40,
            activeDischargeAboveUpper: true
        )

        // Verifies whitespace trimming
        XCTAssertEqual(profile.name, "Night Profile")
        XCTAssertEqual(profile.lowerLimit, 20)
        XCTAssertEqual(profile.upperLimit, 80)
        XCTAssertEqual(profile.heatProtectionCelsius, 40)
        XCTAssertTrue(profile.activeDischargeAboveUpper)

        // Allowed boundary limits
        XCTAssertNoThrow(try BGSavedProfile(name: "Min Lower", lowerLimit: 5, upperLimit: 20))
        XCTAssertNoThrow(try BGSavedProfile(name: "Max Lower", lowerLimit: 95, upperLimit: 100))
        XCTAssertNoThrow(try BGSavedProfile(name: "Max Upper", lowerLimit: 50, upperLimit: 100))
        XCTAssertNoThrow(try BGSavedProfile(name: "Heat 0", lowerLimit: 20, upperLimit: 80, heatProtectionCelsius: 0))
        XCTAssertNoThrow(try BGSavedProfile(name: "Heat 30", lowerLimit: 20, upperLimit: 80, heatProtectionCelsius: 30))
        XCTAssertNoThrow(try BGSavedProfile(name: "Heat 50", lowerLimit: 20, upperLimit: 80, heatProtectionCelsius: 50))

        // 60-character name exactly allowed
        let exact60 = String(repeating: "a", count: 60)
        XCTAssertNoThrow(try BGSavedProfile(name: exact60, lowerLimit: 20, upperLimit: 80))
    }

    func testProfileValidationInvalidRangesThrowErrorsWithoutClamping() {
        // Empty / whitespace name
        XCTAssertThrowsError(try BGSavedProfile(name: "", lowerLimit: 20, upperLimit: 80)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .emptyName)
        }
        XCTAssertThrowsError(try BGSavedProfile(name: "   \n\t  ", lowerLimit: 20, upperLimit: 80)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .emptyName)
        }

        // Name too long (> 60 chars)
        let name61 = String(repeating: "b", count: 61)
        XCTAssertThrowsError(try BGSavedProfile(name: name61, lowerLimit: 20, upperLimit: 80)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .nameTooLong(count: 61, max: 60))
        }

        // Lower limit out of 5...95 range
        XCTAssertThrowsError(try BGSavedProfile(name: "Low", lowerLimit: 4, upperLimit: 80)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidLowerLimit(4))
        }
        XCTAssertThrowsError(try BGSavedProfile(name: "Low", lowerLimit: 96, upperLimit: 98)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidLowerLimit(96))
        }

        // Upper limit out of 20...100 range
        XCTAssertThrowsError(try BGSavedProfile(name: "Up", lowerLimit: 10, upperLimit: 19)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidUpperLimit(19))
        }
        XCTAssertThrowsError(try BGSavedProfile(name: "Up", lowerLimit: 80, upperLimit: 101)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidUpperLimit(101))
        }

        // Upper limit must be strictly greater than lower limit
        XCTAssertThrowsError(try BGSavedProfile(name: "Equal", lowerLimit: 50, upperLimit: 50)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .upperLimitNotGreaterThanLower(lower: 50, upper: 50))
        }
        XCTAssertThrowsError(try BGSavedProfile(name: "Inverted", lowerLimit: 60, upperLimit: 40)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .upperLimitNotGreaterThanLower(lower: 60, upper: 40))
        }

        // Heat protection must be 0 or 30...50
        XCTAssertThrowsError(try BGSavedProfile(name: "HeatLow", lowerLimit: 20, upperLimit: 80, heatProtectionCelsius: 29)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidHeatProtection(29))
        }
        XCTAssertThrowsError(try BGSavedProfile(name: "HeatHigh", lowerLimit: 20, upperLimit: 80, heatProtectionCelsius: 51)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidHeatProtection(51))
        }
        XCTAssertThrowsError(try BGSavedProfile(name: "HeatMid", lowerLimit: 20, upperLimit: 80, heatProtectionCelsius: 15)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidHeatProtection(15))
        }
    }

    // MARK: - Applying to BGConfig Tests

    func testApplyingPreservesBaseUnrelatedAndClearsAppropriateFields() throws {
        let profile = try BGSavedProfile(
            name: "Workstation",
            lowerLimit: 40,
            upperLimit: 75,
            heatProtectionCelsius: 38,
            activeDischargeAboveUpper: true
        )

        var original = BGConfig()
        original.enabled = false
        original.lowerLimit = 15
        original.upperLimit = 90
        original.heatProtectionCelsius = 0
        original.activeDischargeAboveUpper = false
        original.magsafeLed = false // Should be preserved
        original.mode = .pendulum   // Should be preserved

        let now = Date()
        let travelDate = now.addingTimeInterval(3600 * 24)
        let travelID = UUID()
        original.pauseUntil = now.addingTimeInterval(3600)
        original.chargeToFullOnce = true
        original.fullChargeUntil = now.addingTimeInterval(1800)
        original.fullChargeRequestID = UUID()
        original.travelReadyAt = travelDate
        original.travelRequestID = travelID

        let applied = profile.applying(to: original)

        // Applied limits and policies
        XCTAssertTrue(applied.enabled)
        XCTAssertEqual(applied.lowerLimit, 40)
        XCTAssertEqual(applied.upperLimit, 75)
        XCTAssertEqual(applied.heatProtectionCelsius, 38)
        XCTAssertTrue(applied.activeDischargeAboveUpper)

        // Mode preservation
        XCTAssertEqual(applied.mode, .pendulum)

        // Unrelated settings preserved
        XCTAssertFalse(applied.magsafeLed)
        XCTAssertEqual(applied.travelReadyAt, travelDate)
        XCTAssertEqual(applied.travelRequestID, travelID)

        // Pauses and old full charge cleared
        XCTAssertNil(applied.pauseUntil)
        XCTAssertFalse(applied.chargeToFullOnce)
        XCTAssertNil(applied.fullChargeUntil)
        XCTAssertNil(applied.fullChargeRequestID)

        // Matching check
        XCTAssertTrue(profile.matches(applied))
    }

    func testApplyingSwitchesNativeAndDirectModesToAuto() throws {
        let profile = try BGSavedProfile(name: "Normal", lowerLimit: 30, upperLimit: 80)

        var nativeConfig = BGConfig()
        nativeConfig.mode = .native
        XCTAssertEqual(profile.applying(to: nativeConfig).mode, .auto)

        var directConfig = BGConfig()
        directConfig.mode = .direct
        XCTAssertEqual(profile.applying(to: directConfig).mode, .auto)

        var autoConfig = BGConfig()
        autoConfig.mode = .auto
        XCTAssertEqual(profile.applying(to: autoConfig).mode, .auto)
    }

    // MARK: - Collection Export / Import Roundtrip Tests

    func testCollectionRoundtripExportAndImport() throws {
        let p1 = try BGSavedProfile(
            name: "Eco Profile",
            lowerLimit: 40,
            upperLimit: 70,
            heatProtectionCelsius: 35,
            activeDischargeAboveUpper: false
        )
        let p2 = try BGSavedProfile(
            name: "High Battery",
            lowerLimit: 75,
            upperLimit: 95,
            heatProtectionCelsius: 45,
            activeDischargeAboveUpper: true
        )

        let collection = try BGSavedProfileCollection(profiles: [p1, p2])
        let data = try collection.exportData()
        let imported = try BGSavedProfileCollection.importData(data)

        XCTAssertEqual(imported.version, 1)
        XCTAssertEqual(imported.profiles.count, 2)
        XCTAssertEqual(imported, collection)

        let jsonString = try collection.exportJSONString()
        let importedFromString = try BGSavedProfileCollection.importJSONString(jsonString)
        XCTAssertEqual(importedFromString, collection)
    }

    // MARK: - Collection Constraints & Duplicate Rejection Tests

    func testCollectionDuplicateIDRejection() throws {
        let sharedID = UUID()
        let p1 = try BGSavedProfile(id: sharedID, name: "Profile One", lowerLimit: 20, upperLimit: 80)
        let p2 = try BGSavedProfile(id: sharedID, name: "Profile Two", lowerLimit: 30, upperLimit: 85)

        XCTAssertThrowsError(try BGSavedProfileCollection(profiles: [p1, p2])) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .duplicateProfileID(sharedID))
        }
    }

    func testCollectionCaseInsensitiveDuplicateNameRejection() throws {
        let p1 = try BGSavedProfile(name: "Night Profile", lowerLimit: 20, upperLimit: 80)
        let p2 = try BGSavedProfile(name: "night profile", lowerLimit: 30, upperLimit: 85)

        XCTAssertThrowsError(try BGSavedProfileCollection(profiles: [p1, p2])) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .duplicateProfileName("night profile"))
        }

        let p3 = try BGSavedProfile(name: "Desk", lowerLimit: 20, upperLimit: 80)
        let p4 = try BGSavedProfile(name: "DESK", lowerLimit: 30, upperLimit: 85)

        XCTAssertThrowsError(try BGSavedProfileCollection(profiles: [p3, p4])) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .duplicateProfileName("DESK"))
        }
    }

    func testCollectionProfileLimit50() throws {
        var profiles: [BGSavedProfile] = []
        for i in 1...50 {
            profiles.append(try BGSavedProfile(name: "Profile \(i)", lowerLimit: 20, upperLimit: 80))
        }
        XCTAssertNoThrow(try BGSavedProfileCollection(profiles: profiles))

        profiles.append(try BGSavedProfile(name: "Profile 51", lowerLimit: 20, upperLimit: 80))
        XCTAssertThrowsError(try BGSavedProfileCollection(profiles: profiles)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .tooManyProfiles(count: 51, max: 50))
        }
    }

    // MARK: - Import Security, Schema & Size Tests

    func testImportRejectsOversizedPayload() {
        let maxAllowed = 256 * 1024
        let oversizedData = Data(repeating: 0x20, count: maxAllowed + 1)

        XCTAssertThrowsError(try BGSavedProfileCollection.importData(oversizedData)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .payloadTooLarge(bytes: maxAllowed + 1, maxBytes: maxAllowed))
        }
    }

    func testImportRejectsUnknownSchemaVersionAtomically() {
        let invalidVersionJSON = """
        {
            "version": 2,
            "profiles": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BGSavedProfileCollection.importData(invalidVersionJSON)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .unsupportedSchemaVersion(2))
        }
    }

    func testImportRejectsMalformedJSONAtomically() {
        let malformedJSON = "{ \"version\": 1, \"profiles\": [ broken json".data(using: .utf8)!

        XCTAssertThrowsError(try BGSavedProfileCollection.importData(malformedJSON)) { error in
            guard case .invalidSchema = (error as? BGSavedProfileError) else {
                XCTFail("Expected .invalidSchema but got \(error)")
                return
            }
        }
    }

    func testImportRejectsUnknownProfileFieldsStrictly() {
        let profileWithSecretJSON = """
        {
            "version": 1,
            "profiles": [
                {
                    "id": "\(UUID().uuidString)",
                    "name": "Secret Leak",
                    "lowerLimit": 20,
                    "upperLimit": 80,
                    "heatProtectionCelsius": 0,
                    "activeDischargeAboveUpper": false,
                    "api_token": "secret_super_token_123"
                }
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BGSavedProfileCollection.importData(profileWithSecretJSON)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .unknownProfileField("api_token"))
        }
    }

    func testImportRejectsUnknownCollectionFieldsStrictly() {
        let collectionWithSecretJSON = """
        {
            "version": 1,
            "secret_key": "top_secret_value",
            "profiles": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BGSavedProfileCollection.importData(collectionWithSecretJSON)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .unknownCollectionField("secret_key"))
        }
    }

    func testImportRejectsInvalidProfileValuesWithoutClamping() {
        let invalidProfileJSON = """
        {
            "version": 1,
            "profiles": [
                {
                    "id": "\(UUID().uuidString)",
                    "name": "Clamping Test",
                    "lowerLimit": 1,
                    "upperLimit": 80
                }
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BGSavedProfileCollection.importData(invalidProfileJSON)) { error in
            XCTAssertEqual(error as? BGSavedProfileError, .invalidLowerLimit(1))
        }
    }
}
