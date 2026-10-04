import Foundation

public struct BGPowerFlowSample: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let inputWatts: Double?
    public let batteryWatts: Double?
    public let adapterRatedWatts: Double?
    public let hardwarePercent: Double?
    public let source: String

    public init(
        sampledAt: Date = Date(),
        inputWatts: Double? = nil,
        batteryWatts: Double? = nil,
        adapterRatedWatts: Double? = nil,
        hardwarePercent: Double? = nil,
        source: String = "AppleSmartBattery"
    ) {
        self.sampledAt = sampledAt

        if let inputWatts, inputWatts.isFinite, inputWatts >= 0 {
            self.inputWatts = inputWatts
        } else {
            self.inputWatts = nil
        }

        if let batteryWatts, batteryWatts.isFinite {
            self.batteryWatts = batteryWatts
        } else {
            self.batteryWatts = nil
        }

        if let adapterRatedWatts, adapterRatedWatts.isFinite, adapterRatedWatts > 0 {
            self.adapterRatedWatts = adapterRatedWatts
        } else {
            self.adapterRatedWatts = nil
        }

        if let hardwarePercent, hardwarePercent.isFinite, (0...100).contains(hardwarePercent) {
            self.hardwarePercent = hardwarePercent
        } else {
            self.hardwarePercent = nil
        }

        self.source = source
    }

    public var systemWatts: Double? {
        guard let inputWatts, let batteryWatts else { return nil }
        let system = inputWatts - batteryWatts
        guard system.isFinite, system >= 0 else { return nil }
        return system
    }

    public func isFresh(at: Date = Date()) -> Bool {
        let age = at.timeIntervalSince(sampledAt)
        return age >= -5.0 && age <= 10.0
    }

    private enum CodingKeys: String, CodingKey {
        case sampledAt
        case inputWatts
        case batteryWatts
        case adapterRatedWatts
        case hardwarePercent
        case source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sampledAt = try container.decode(Date.self, forKey: .sampledAt)
        let inputWatts = try container.decodeIfPresent(Double.self, forKey: .inputWatts)
        let batteryWatts = try container.decodeIfPresent(Double.self, forKey: .batteryWatts)
        let adapterRatedWatts = try container.decodeIfPresent(Double.self, forKey: .adapterRatedWatts)
        let hardwarePercent = try container.decodeIfPresent(Double.self, forKey: .hardwarePercent)
        let source = try container.decode(String.self, forKey: .source)

        self.init(
            sampledAt: sampledAt,
            inputWatts: inputWatts,
            batteryWatts: batteryWatts,
            adapterRatedWatts: adapterRatedWatts,
            hardwarePercent: hardwarePercent,
            source: source
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampledAt, forKey: .sampledAt)
        try container.encodeIfPresent(inputWatts, forKey: .inputWatts)
        try container.encodeIfPresent(batteryWatts, forKey: .batteryWatts)
        try container.encodeIfPresent(adapterRatedWatts, forKey: .adapterRatedWatts)
        try container.encodeIfPresent(hardwarePercent, forKey: .hardwarePercent)
        try container.encode(source, forKey: .source)
    }
}
