import Foundation
import Darwin
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct AtomicActionTests {
    private func fixture(_ config: BGConfig = BGConfig()) throws -> (URL, URL) {
        let directory = URL(fileURLWithPath: "/tmp/BGA-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(config).write(to: url)
        return (directory, url)
    }

    @Test func explicitOffAndProfileApplyAgainstCurrentServiceState() throws {
        var current = BGConfig(); current.enabled = true; current.heatProtectionCelsius = 43
        let (directory, url) = try fixture(current)
        defer { try? FileManager.default.removeItem(at: directory) }
        let off = BGConfigRequest(action: .init(action: .protection, enabled: false))
        let saved = try ConfigServer.apply(off, peerUID: 501, consoleUID: 501, configURL: url)
        #expect(!saved.enabled && saved.heatProtectionCelsius == 43)
        var intervening = saved; intervening.upperLimit = 85
        try BGJSON.encoder().encode(intervening).write(to: url)
        let profile = try ConfigServer.apply(.init(action: .init(action: .profile, profile: "desk")),
            peerUID: 501, consoleUID: 501, configURL: url)
        #expect(profile.enabled && profile.lowerLimit == 55 && profile.upperLimit == 60)
        #expect(profile.heatProtectionCelsius == 43)
    }

    @Test func malformedVersionQueryAndUnauthorizedActionNeverWrite() throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try Data(contentsOf: url)
        let request = BGConfigRequest(action: .init(action: .protection, enabled: false))
        #expect(throws: (any Error).self) {
            try ConfigServer.apply(request, peerUID: 502, consoleUID: 501, configURL: url)
        }
        let encoded = try BGJSON.encoder().encode(request)
        for mutation in ["legacy", "query", "missing-action"] {
            var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            if mutation == "legacy" { json["protocolVersion"] = 1 }
            if mutation == "query" { json["queryOnly"] = true }
            if mutation == "missing-action" { json.removeValue(forKey: "action") }
            let bad = try BGJSON.decoder().decode(BGConfigRequest.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(throws: (any Error).self) {
                try ConfigServer.apply(bad, peerUID: 501, consoleUID: 501, configURL: url)
            }
        }
        let invalid = BGConfigRequest(action: .init(action: .pause, minutes: 0))
        #expect(throws: BGChargingActionError.self) {
            try ConfigServer.apply(invalid, peerUID: 501, consoleUID: 501, configURL: url)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func versionTwoCommandCrossesRealSocketAndRejectsLegacyReply() async throws {
        for legacy in [false, true] {
            let (directory, url) = try fixture()
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("test.sock").path
            let listener = socket(AF_UNIX, SOCK_STREAM, 0)
            guard listener >= 0 else { throw BGConfigWire.posixError() }
            defer { _ = close(listener) }
            try BGConfigWire.configure(listener)
            var address = try BGConfigWire.address(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(listener, 1) == 0 else { throw BGConfigWire.posixError() }
            let server = Task.detached {
                let deadline = ProcessInfo.processInfo.systemUptime + 1
                try BGConfigWire.wait(listener, for: Int16(POLLIN), until: deadline)
                let client = accept(listener, nil, nil)
                guard client >= 0 else { throw BGConfigWire.posixError() }
                defer { _ = close(client) }
                try BGConfigWire.configure(client)
                let request = try BGConfigWire.receive(BGConfigRequest.self, from: client, until: deadline)
                #expect(request.protocolVersion == 2)
                let response: BGConfigResponse
                if legacy {
                    response = BGConfigResponse(error: "Unsupported version")
                } else {
                    let uid = try BGConfigWire.peerUID(client)
                    let saved = try ConfigServer.apply(request, peerUID: uid, consoleUID: geteuid(), configURL: url)
                    response = BGConfigResponse(config: saved, protocolVersion: request.protocolVersion)
                }
                try BGConfigWire.send(response, to: client, until: deadline)
            }
            let request = BGConfigRequest(action: .init(action: .protection, enabled: false))
            if legacy {
                #expect(throws: BGConfigIPCError.self) {
                    try BGConfigClient.exchange(request, socketPath: path, expectedServerUID: geteuid())
                }
                #expect(try BGConfigFile.read(at: url).enabled)
            } else {
                let saved = try BGConfigClient.exchange(request, socketPath: path, expectedServerUID: geteuid())
                #expect(!saved.enabled)
                #expect(try BGConfigFile.read(at: url) == saved)
            }
            try await server.value
        }
    }
}
