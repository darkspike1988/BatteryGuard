import AppIntents
import Foundation
import BatteryGuardShared

public enum BatteryReadIntentPayload {
    public struct StatusResponse: Codable, Equatable, Sendable {
        public let available: Bool
        public let status: BGStatus?

        public init(available: Bool, status: BGStatus? = nil) {
            self.available = available
            self.status = status
        }
    }

    public typealias StatusPayload = StatusResponse

    public struct PowerFlowResponse: Codable, Equatable, Sendable {
        public let available: Bool
        public let sampledAt: Date?
        public let inputWatts: Double?
        public let batteryWatts: Double?
        public let systemWatts: Double?
        public let adapterRatedWatts: Double?
        public let hardwarePercent: Double?
        public let source: String?

        public init(
            available: Bool,
            sampledAt: Date? = nil,
            inputWatts: Double? = nil,
            batteryWatts: Double? = nil,
            systemWatts: Double? = nil,
            adapterRatedWatts: Double? = nil,
            hardwarePercent: Double? = nil,
            source: String? = nil
        ) {
            self.available = available
            self.sampledAt = sampledAt
            self.inputWatts = inputWatts
            self.batteryWatts = batteryWatts
            self.systemWatts = systemWatts
            self.adapterRatedWatts = adapterRatedWatts
            self.hardwarePercent = hardwarePercent
            self.source = source
        }
    }

    public typealias PowerFlowPayload = PowerFlowResponse

    public struct TargetResponse: Codable, Equatable, Sendable {
        public let available: Bool
        public let targetUpperLimit: Int?
        public let appliedUpperLimit: Int?
        public let nativeChargeLimit: Int?
        public let controlPath: BGControlPath?
        public let state: BGEffectivenessState?
        public let desktopProfileActive: Bool?

        public init(available: Bool, targetUpperLimit: Int? = nil, appliedUpperLimit: Int? = nil,
                    nativeChargeLimit: Int? = nil, controlPath: BGControlPath? = nil,
                    state: BGEffectivenessState? = nil, desktopProfileActive: Bool? = nil) {
            self.available = available
            self.targetUpperLimit = targetUpperLimit
            self.appliedUpperLimit = appliedUpperLimit
            self.nativeChargeLimit = nativeChargeLimit
            self.controlPath = controlPath
            self.state = state
            self.desktopProfileActive = desktopProfileActive
        }
    }

    public static func targetJSON(statusData: Data?, configData: Data?, at: Date = Date()) throws -> String {
        guard let statusData, let configData,
              let status = try? BGJSON.decoder().decode(BGStatus.self, from: statusData),
              let config = try? BGJSON.decoder().decode(BGConfig.self, from: configData) else {
            return String(decoding: try BGJSON.encoder().encode(TargetResponse(available: false)), as: UTF8.self)
        }
        let age = at.timeIntervalSince(status.updatedAt)
        let fresh = (-5...60).contains(age)
            && status.daemonVersion.compare(AppVersion.requiredDaemon, options: .numeric) != .orderedAscending
        guard fresh else {
            return String(decoding: try BGJSON.encoder().encode(TargetResponse(available: false)), as: UTF8.self)
        }
        let result = BGEffectiveness.evaluate(config: config, status: status,
                                              daemonActive: true, daemonCurrent: true, now: at)
        let payload = TargetResponse(available: true,
                                     targetUpperLimit: result.targetUpperLimit,
                                     appliedUpperLimit: result.appliedUpperLimit,
                                     nativeChargeLimit: result.nativeChargeLimit,
                                     controlPath: result.controlPath,
                                     state: result.state,
                                     desktopProfileActive: status.desktopProfileActive)
        return String(decoding: try BGJSON.encoder().encode(payload), as: UTF8.self)
    }

    public static func statusJSON(data: Data?, at: Date = Date()) throws -> String {
        guard let data else {
            let payload = StatusResponse(available: false, status: nil)
            let encoded = try BGJSON.encoder().encode(payload)
            return String(decoding: encoded, as: UTF8.self)
        }

        let status = try BGJSON.decoder().decode(BGStatus.self, from: data)
        let age = at.timeIntervalSince(status.updatedAt)
        let isFresh = (age >= -5.0 && age <= 60.0) && status.hasBatteryPercent

        let payload = isFresh
            ? StatusResponse(available: true, status: status)
            : StatusResponse(available: false, status: nil)

        let encoded = try BGJSON.encoder().encode(payload)
        return String(decoding: encoded, as: UTF8.self)
    }

    public static func powerFlowJSON(sample: BGPowerFlowSample?, at: Date = Date()) throws -> String {
        guard let sample,
              sample.isFresh(at: at),
              (sample.inputWatts != nil || sample.batteryWatts != nil) else {
            let payload = PowerFlowResponse(available: false)
            let encoded = try BGJSON.encoder().encode(payload)
            return String(decoding: encoded, as: UTF8.self)
        }

        let payload = PowerFlowResponse(
            available: true,
            sampledAt: sample.sampledAt,
            inputWatts: sample.inputWatts,
            batteryWatts: sample.batteryWatts,
            systemWatts: sample.systemWatts,
            adapterRatedWatts: sample.adapterRatedWatts,
            hardwarePercent: sample.hardwarePercent,
            source: sample.source
        )

        let encoded = try BGJSON.encoder().encode(payload)
        return String(decoding: encoded, as: UTF8.self)
    }
}

public func powerFlowJSON(sample: BGPowerFlowSample?, at: Date = Date()) throws -> String {
    try BatteryReadIntentPayload.powerFlowJSON(sample: sample, at: at)
}

@available(macOS 14.0, *)
public struct ReadBatteryStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Akkustatus lesen"
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let url = URL(fileURLWithPath: BGPaths.status)
        let data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch {
            data = nil
        }
        let json = try BatteryReadIntentPayload.statusJSON(data: data)
        return .result(value: json)
    }
}

@available(macOS 14.0, *)
public struct ReadPowerFlowIntent: AppIntent {
    public static let title: LocalizedStringResource = "Energiefluss lesen"
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sample = PowerFlowReader.read()
        let json = try BatteryReadIntentPayload.powerFlowJSON(sample: sample)
        return .result(value: json)
    }
}

@available(macOS 14.0, *)
public struct ReadBatteryTargetIntent: AppIntent {
    public static let title: LocalizedStringResource = "Wirksames Ladeziel lesen"
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let statusData = try? Data(contentsOf: URL(fileURLWithPath: BGPaths.status))
        let configData = try? Data(contentsOf: URL(fileURLWithPath: BGPaths.config))
        let json = try BatteryReadIntentPayload.targetJSON(statusData: statusData, configData: configData)
        return .result(value: json)
    }
}

@available(macOS 14.0, *)
public struct BGuardShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
            AppShortcut(
                intent: ReadBatteryStatusIntent(),
                phrases: [
                    "\(.applicationName) Akkustatus",
                    "Akkustatus mit \(.applicationName) lesen"
                ],
                shortTitle: "Akkustatus",
                systemImageName: "battery.100"
            )
            AppShortcut(
                intent: ReadPowerFlowIntent(),
                phrases: [
                    "\(.applicationName) Energiefluss",
                    "Energiefluss mit \(.applicationName) lesen"
                ],
                shortTitle: "Energiefluss",
                systemImageName: "bolt.horizontal"
            )
            AppShortcut(
                intent: ReadBatteryTargetIntent(),
                phrases: [
                    "\(.applicationName) Ladeziel",
                    "Wirksames Ladeziel mit \(.applicationName) lesen"
                ],
                shortTitle: "Ladeziel",
                systemImageName: "target"
            )
    }
}
