import XCTest
import Foundation
import AppIntents
import BatteryGuardShared
@testable import BatteryGuard

@available(macOS 14.0, *)
final class BatteryReadIntentsTests: XCTestCase {

    private func parseJSON(_ jsonString: String) throws -> [String: Any] {
        let data = Data(jsonString.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Parsed JSON is not a dictionary: \(jsonString)")
            return [:]
        }
        return object
    }

    // MARK: - Status JSON Tests

    func testStatusJSON_missingData_returnsAvailableFalseAndNoNumericStatus() throws {
        let jsonString = try BatteryReadIntentPayload.statusJSON(data: nil)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
        XCTAssertNil(dict["status"])
        XCTAssertNil(dict["percent"])
        XCTAssertNil(dict["watts"])
    }

    func testStatusJSON_malformedData_throwsDecodeError() {
        let malformedData = Data("this is not valid json".utf8)
        XCTAssertThrowsError(try BatteryReadIntentPayload.statusJSON(data: malformedData))
    }

    func testStatusJSON_freshData_returnsAvailableTrueAndStatus() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var status = BGStatus()
        status.percent = 84
        status.pluggedIn = true
        status.state = .charging
        status.watts = 28.5
        status.updatedAt = now.addingTimeInterval(-15) // 15 seconds old (within -5...60)

        let data = try BGJSON.encoder().encode(status)
        let jsonString = try BatteryReadIntentPayload.statusJSON(data: data, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        let statusDict = try XCTUnwrap(dict["status"] as? [String: Any])
        XCTAssertEqual(statusDict["percent"] as? Int, 84)
        XCTAssertEqual(statusDict["pluggedIn"] as? Bool, true)
        XCTAssertEqual(statusDict["state"] as? String, "charging")
        XCTAssertEqual(statusDict["watts"] as? Double, 28.5)
    }

    func testStatusJSON_staleData_returnsAvailableFalseAndNoNumericStatus() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var status = BGStatus()
        status.percent = 70
        status.watts = 15.0
        status.updatedAt = now.addingTimeInterval(-61) // 61 seconds old (exceeds 60)

        let data = try BGJSON.encoder().encode(status)
        let jsonString = try BatteryReadIntentPayload.statusJSON(data: data, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
        XCTAssertNil(dict["status"])
        XCTAssertNil(dict["percent"])
        XCTAssertNil(dict["watts"])
    }

    func testStatusJSON_futureData_beyondTolerance_returnsAvailableFalse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var status = BGStatus()
        status.percent = 90
        status.updatedAt = now.addingTimeInterval(10) // 10s in future (age -10 < -5)

        let data = try BGJSON.encoder().encode(status)
        let jsonString = try BatteryReadIntentPayload.statusJSON(data: data, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
        XCTAssertNil(dict["status"])
    }

    func testStatusJSON_futureData_withinTolerance_returnsAvailableTrue() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var status = BGStatus()
        status.percent = 90
        status.updatedAt = now.addingTimeInterval(3) // 3s in future (age -3 in -5...60)

        let data = try BGJSON.encoder().encode(status)
        let jsonString = try BatteryReadIntentPayload.statusJSON(data: data, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        XCTAssertNotNil(dict["status"])
    }

    // MARK: - Power Flow JSON Tests

    func testPowerFlowJSON_missingSample_returnsAvailableFalse() throws {
        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: nil)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
        XCTAssertNil(dict["systemWatts"])
        XCTAssertNil(dict["inputWatts"])
        XCTAssertNil(dict["batteryWatts"])
    }

    func testPowerFlowJSON_staleSample_returnsAvailableFalse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now.addingTimeInterval(-12), // 12s old (exceeds 10)
            inputWatts: 45.0,
            batteryWatts: 20.0
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
        XCTAssertNil(dict["systemWatts"])
    }

    func testPowerFlowJSON_futureSample_beyondTolerance_returnsAvailableFalse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now.addingTimeInterval(8), // 8s in future (age -8 < -5)
            inputWatts: 45.0,
            batteryWatts: 20.0
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
    }

    func testPowerFlowJSON_futureSample_withinTolerance_returnsAvailableTrue() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now.addingTimeInterval(2), // 2s in future (age -2 in -5...10)
            inputWatts: 45.0,
            batteryWatts: 20.0
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        XCTAssertEqual(dict["systemWatts"] as? Double, 25.0)
    }

    func testPowerFlowJSON_noInputAndNoBatteryWatts_returnsAvailableFalse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now,
            inputWatts: nil,
            batteryWatts: nil,
            adapterRatedWatts: 96.0,
            hardwarePercent: 80.0
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, false)
    }

    func testPowerFlowJSON_signedFlow_charging() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now.addingTimeInterval(-2),
            inputWatts: 65.0,
            batteryWatts: 25.0 // positive -> charging
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        XCTAssertEqual(dict["inputWatts"] as? Double, 65.0)
        XCTAssertEqual(dict["batteryWatts"] as? Double, 25.0)
        XCTAssertEqual(dict["systemWatts"] as? Double, 40.0) // 65 - 25 = 40
    }

    func testPowerFlowJSON_signedFlow_discharging() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now.addingTimeInterval(-2),
            inputWatts: 0.0,
            batteryWatts: -18.5 // negative -> discharging
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        XCTAssertEqual(dict["inputWatts"] as? Double, 0.0)
        XCTAssertEqual(dict["batteryWatts"] as? Double, -18.5)
        XCTAssertEqual(dict["systemWatts"] as? Double, 18.5) // 0 - (-18.5) = 18.5
    }

    func testPowerFlowJSON_ratingNeverConsumption() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now.addingTimeInterval(-1),
            inputWatts: 50.0,
            batteryWatts: 15.0,
            adapterRatedWatts: 140.0 // rating, never consumption
        )

        let jsonString = try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        XCTAssertEqual(dict["adapterRatedWatts"] as? Double, 140.0)
        XCTAssertEqual(dict["inputWatts"] as? Double, 50.0)
        XCTAssertEqual(dict["batteryWatts"] as? Double, 15.0)
        // systemWatts MUST be inputWatts - batteryWatts (50 - 15 = 35), NOT adapterRatedWatts - batteryWatts (140 - 15 = 125)
        XCTAssertEqual(dict["systemWatts"] as? Double, 35.0)

        // When inputWatts is missing, adapter rating alone must never be used to derive systemWatts
        let ratingOnlySample = BGPowerFlowSample(
            sampledAt: now,
            inputWatts: nil,
            batteryWatts: 10.0,
            adapterRatedWatts: 140.0
        )
        let ratingOnlyJSON = try BatteryReadIntentPayload.powerFlowJSON(sample: ratingOnlySample, at: now)
        let ratingOnlyDict = try parseJSON(ratingOnlyJSON)

        XCTAssertEqual(ratingOnlyDict["available"] as? Bool, true)
        XCTAssertNil(ratingOnlyDict["systemWatts"])
    }

    func testTopLevelPowerFlowJSONHelper() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = BGPowerFlowSample(
            sampledAt: now,
            inputWatts: 30.0,
            batteryWatts: 10.0
        )
        let jsonString = try powerFlowJSON(sample: sample, at: now)
        let dict = try parseJSON(jsonString)

        XCTAssertEqual(dict["available"] as? Bool, true)
        XCTAssertEqual(dict["systemWatts"] as? Double, 20.0)
    }

    // MARK: - Intents and Shortcuts Provider Metadata Tests

    func testReadBatteryStatusIntentMetadata() {
        XCTAssertFalse(ReadBatteryStatusIntent.openAppWhenRun)
        XCTAssertEqual(ReadBatteryStatusIntent.title.key, "Akkustatus lesen")
    }

    func testReadPowerFlowIntentMetadata() {
        XCTAssertFalse(ReadPowerFlowIntent.openAppWhenRun)
        XCTAssertEqual(ReadPowerFlowIntent.title.key, "Energiefluss lesen")
    }

    func testBGuardShortcutsProviderMetadata() {
        let shortcuts = BGuardShortcutsProvider.appShortcuts
        XCTAssertEqual(shortcuts.count, 2)
    }
}
