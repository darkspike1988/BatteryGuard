import Foundation
import Testing
import BatteryGuardShared
@testable import BatteryGuard

@MainActor
struct PowerFlowAPITests {
    private static let path = "/api/v1/power-flow"
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Single construction point for the sample so the shared-model contract is adapted in one place.
    private func sample(input: Double?, battery: Double?, rating: Double?, sampledAt: Date) -> BGPowerFlowSample {
        BGPowerFlowSample(sampledAt: sampledAt, inputWatts: input, batteryWatts: battery, adapterRatedWatts: rating)
    }

    private func object(_ response: LocalHTTPResponse) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: response.jsonData) as? [String: Any])
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// Optional power fields may be absent or null when unavailable; any non-null `*Watts` value is a violation.
    private func nonNullPowerFields(_ body: [String: Any]) -> [String] {
        body.filter { $0.key.hasSuffix("Watts") && !($0.value is NSNull) }.map(\.key).sorted()
    }

    @Test func freshSampleIsAvailableAndSystemPowerIsDerivedNotAdapterRating() throws {
        let f = try LocalAPITests().fixture(); defer { f.cleanUp() }
        f.status.powerFlow = sample(input: 12, battery: 0, rating: 65, sampledAt: Self.now.addingTimeInterval(-1))
        let response = f.api.respond(to: f.request(Self.path), now: Self.now)
        #expect(response.status == 200)
        let body = try object(response)
        #expect(body["available"] as? Bool == true)
        #expect(number(body["systemWatts"]) == 12)
        #expect(number(body["systemWatts"]) != 65)
    }

    @Test func sampleElevenSecondsOldIsUnavailableWithoutPowerFields() throws {
        let f = try LocalAPITests().fixture(); defer { f.cleanUp() }
        f.status.powerFlow = sample(input: 12, battery: 0, rating: 65, sampledAt: Self.now.addingTimeInterval(-11))
        let response = f.api.respond(to: f.request(Self.path), now: Self.now)
        #expect(response.status == 200)
        let body = try object(response)
        #expect(body["available"] as? Bool == false)
        #expect(nonNullPowerFields(body).isEmpty)
    }

    @Test func missingSampleIsUnavailable() throws {
        let f = try LocalAPITests().fixture(); defer { f.cleanUp() }
        f.status.powerFlow = nil
        let response = f.api.respond(to: f.request(Self.path), now: Self.now)
        #expect(response.status == 200)
        let body = try object(response)
        #expect(body["available"] as? Bool == false)
        #expect(nonNullPowerFields(body).isEmpty)
    }

    @Test func sampleWithAllPowersNilIsUnavailableEvenWithAdapterRating() throws {
        let f = try LocalAPITests().fixture(); defer { f.cleanUp() }
        f.status.powerFlow = sample(input: nil, battery: nil, rating: 65, sampledAt: Self.now.addingTimeInterval(-1))
        let response = f.api.respond(to: f.request(Self.path), now: Self.now)
        #expect(response.status == 200)
        let body = try object(response)
        #expect(body["available"] as? Bool == false)
        #expect(nonNullPowerFields(body).isEmpty)
    }

    @Test func requestValidationRejectsUnauthenticatedWrongMethodQueryAndBody() throws {
        let f = try LocalAPITests().fixture(); defer { f.cleanUp() }
        f.status.powerFlow = sample(input: 12, battery: 0, rating: 65, sampledAt: Self.now.addingTimeInterval(-1))
        #expect(f.api.respond(to: f.request(Self.path, overrides: ["authorization": "Bearer wrong"]), now: Self.now).status == 401)
        #expect(f.api.respond(to: f.request(Self.path, method: "POST"), now: Self.now).status == 405)
        #expect(f.api.respond(to: f.request(Self.path + "?x=1"), now: Self.now).status == 400)
        #expect(f.api.respond(to: f.request(Self.path, json: "{}"), now: Self.now).status == 400)
    }
}
