import Foundation
import Darwin
import Testing
import BatteryGuardShared
@testable import batteryguardd

struct ConfigIPCTests {
    private func fixture() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: url)
        return (directory, url)
    }

    private func pair() throws -> (Int32, Int32) {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw BGConfigWire.posixError() }
        do {
            try BGConfigWire.configure(descriptors[0])
            try BGConfigWire.configure(descriptors[1])
        } catch {
            _ = close(descriptors[0]); _ = close(descriptors[1]); throw error
        }
        return (descriptors[0], descriptors[1])
    }

    @Test func peerPolicyRejectsBackgroundUsersAndTracksConsoleSwitch() {
        #expect(BGConfigPeerPolicy.allows(peerUID: 0, consoleUID: nil))
        #expect(BGConfigPeerPolicy.allows(peerUID: 501, consoleUID: 501))
        #expect(!BGConfigPeerPolicy.allows(peerUID: 501, consoleUID: nil))
        #expect(!BGConfigPeerPolicy.allows(peerUID: 501, consoleUID: 0))
        #expect(!BGConfigPeerPolicy.allows(peerUID: 501, consoleUID: 502))
        #expect(BGConfigPeerPolicy.allows(peerUID: 502, consoleUID: 502))
    }

    @Test func typedRequestMergesWithoutResurrectingDaemonChanges() throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var baseline = BGConfig()
        baseline.chargeToFullOnce = true
        baseline.fullChargeUntil = Date().addingTimeInterval(3600)
        var desired = baseline
        desired.upperLimit = 90
        // The on-disk daemon state has already completed the one-off full charge.
        let saved = try ConfigServer.apply(BGConfigRequest(baseline: baseline, desired: desired),
                                           peerUID: 501, consoleUID: 501, configURL: url)
        #expect(saved.upperLimit == 90)
        #expect(!saved.chargeToFullOnce)
        #expect(saved.fullChargeUntil == nil)
    }

    @Test func unauthorizedAndUnknownProtocolCannotChangeFile() throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try Data(contentsOf: url)
        var desired = BGConfig(); desired.enabled = false
        let request = BGConfigRequest(baseline: BGConfig(), desired: desired)
        #expect(throws: (any Error).self) {
            try ConfigServer.apply(request, peerUID: 502, consoleUID: 501, configURL: url)
        }
        let encoded = try BGJSON.encoder().encode(request)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json["protocolVersion"] = 99
        let invalid = try BGJSON.decoder().decode(BGConfigRequest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: (any Error).self) {
            try ConfigServer.apply(invalid, peerUID: 501, consoleUID: 501, configURL: url)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func queryIsAuthenticatedAndNeverWritesDesiredSettings() throws {
        let (directory, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try Data(contentsOf: url)
        var desired = BGConfig(); desired.enabled = false; desired.upperLimit = 50
        let query = BGConfigRequest(baseline: BGConfig(), desired: desired, queryOnly: true)
        let result = try ConfigServer.apply(query, peerUID: 501, consoleUID: 501, configURL: url)
        #expect(result.enabled && result.upperLimit == 80)
        #expect(try Data(contentsOf: url) == original)
        #expect(throws: (any Error).self) {
            try ConfigServer.apply(query, peerUID: 502, consoleUID: 501, configURL: url)
        }
    }

    @Test func framedSocketRoundTripAndOversizedFrameRejection() throws {
        let (writer, reader) = try pair()
        defer { _ = close(writer); _ = close(reader) }
        var desired = BGConfig(); desired.upperLimit = 90
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        try BGConfigWire.send(BGConfigRequest(baseline: BGConfig(), desired: desired), to: writer, until: deadline)
        let received = try BGConfigWire.receive(BGConfigRequest.self, from: reader, until: deadline)
        #expect(received.desired.upperLimit == 90)
        #expect(try BGConfigWire.peerUID(reader) == geteuid())
        var tooLarge = UInt32(BGConfigWire.maximumBytes + 1).bigEndian
        let sent = withUnsafeBytes(of: &tooLarge) { Darwin.send(writer, $0.baseAddress, $0.count, 0) }
        #expect(sent == 4)
        #expect(throws: (any Error).self) {
            try BGConfigWire.receive(BGConfigRequest.self, from: reader, until: deadline)
        }
    }

    @Test func truncatedFrameHonorsAbsoluteDeadline() throws {
        let (writer, reader) = try pair()
        defer { _ = close(writer); _ = close(reader) }
        var length = UInt32(100).bigEndian
        _ = withUnsafeBytes(of: &length) { Darwin.send(writer, $0.baseAddress, $0.count, 0) }
        let partial = Data("{".utf8)
        _ = partial.withUnsafeBytes { Darwin.send(writer, $0.baseAddress, $0.count, 0) }
        let before = ProcessInfo.processInfo.systemUptime
        #expect(throws: (any Error).self) {
            try BGConfigWire.receive(BGConfigRequest.self, from: reader, until: before + 0.05)
        }
        #expect(ProcessInfo.processInfo.systemUptime - before < 1)
    }

    @Test func clientRejectsUntrustedServerBeforeSendingConfig() throws {
        // A short path avoids Darwin's sockaddr_un limit without touching production paths.
        let directory = URL(fileURLWithPath: "/tmp/BGIPC-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
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
        #expect(throws: (any Error).self) {
            try BGConfigClient.exchange(BGConfigRequest(baseline: BGConfig(), desired: BGConfig()),
                                        socketPath: path, expectedServerUID: geteuid() + 1)
        }
        let client = accept(listener, nil, nil)
        guard client >= 0 else { throw BGConfigWire.posixError() }
        defer { _ = close(client) }
        var byte: UInt8 = 0
        #expect(recv(client, &byte, 1, 0) == 0) // Closed without disclosing a request.
    }
}
