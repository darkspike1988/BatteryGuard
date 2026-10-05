import Darwin
import Foundation
import Testing
@testable import BatteryGuard

/// Real loopback acceptance tests; no app, daemon, or user configuration is started.
struct SlowHTTPConnectionsTests {
    private final class Saves: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        let url: URL
        init(_ url: URL) { self.url = url }
        func save(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
            lock.lock()
            defer { lock.unlock() }
            do {
                try request.body.write(to: url, options: .atomic)
                value += 1
                return LocalHTTPResponse(jsonData: Data("{}".utf8))
            } catch { return LocalHTTPResponse(status: 500, jsonData: Data("{}".utf8)) }
        }
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct SocketFailure: Error { let operation: String; let code: Int32 }
    private final class Peer {
        let fd: Int32
        init(port: UInt16) throws {
            fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw SocketFailure(operation: "socket", code: errno) }
            var noSignal: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var address = Self.address(port)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else {
                let code = errno
                close(fd)
                throw SocketFailure(operation: "connect", code: code)
            }
        }
        deinit { close(fd) }
        static func address(_ port: UInt16) -> sockaddr_in {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            return address
        }
        @discardableResult func send(_ text: String) -> Bool {
            let bytes = Array(text.utf8)
            return bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) == $0.count }
        }
        /// Returns nil on timeout; empty data means EOF/reset with no HTTP response.
        func response(timeout: TimeInterval) throws -> Data? {
            var result = Data()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1000))
                let ready = poll(&descriptor, 1, remaining)
                if ready == 0 { return nil }
                if ready < 0 {
                    if errno == EINTR { continue }
                    throw SocketFailure(operation: "poll", code: errno)
                }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = recv(fd, &bytes, bytes.count, 0)
                if count <= 0 { return result }
                result.append(contentsOf: bytes.prefix(count))
            }
            return nil
        }
    }

    private func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketFailure(operation: "socket", code: errno) }
        defer { close(fd) }
        var address = Peer.address(0)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw SocketFailure(operation: "bind", code: errno) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        guard named == 0 else { throw SocketFailure(operation: "getsockname", code: errno) }
        return UInt16(bigEndian: address.sin_port)
    }

    private func start(_ server: LocalHTTPServer, port: UInt16, saves: Saves) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try server.start(port: port, onReady: { continuation.resume() },
                                 onFailure: { continuation.resume(throwing: SocketFailure(operation: $0, code: 0)) },
                                 handler: { saves.save($0) })
            } catch { continuation.resume(throwing: error) }
        }
    }

    private let prefix = "POST /v1/config HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n"

    @Test func eightSlowRequestsAreAcceptedAndNinthIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = Saves(directory.appendingPathComponent("config.json"))
        let server = LocalHTTPServer()
        defer { server.stop() }
        let port = try availablePort()
        try await start(server, port: port, saves: saves)
        var peers: [Peer] = []
        for _ in 0..<8 {
            let peer = try Peer(port: port)
            #expect(peer.send(prefix + "{"))
            peers.append(peer)
        }
        let ninth = try Peer(port: port)
        _ = ninth.send(prefix + "{}")
        let rejected = try #require(try ninth.response(timeout: 2))
        #expect(rejected.isEmpty)
        #expect(saves.count == 0)
        // Every admitted partial request must still complete successfully.
        for peer in peers { #expect(peer.send("}")) }
        for peer in peers {
            let response = try #require(try peer.response(timeout: 2))
            #expect(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 200 "))
        }
        #expect(saves.count == 8)
        #expect(try Data(contentsOf: saves.url) == Data("{}".utf8))
    }

    @Test func absoluteDeadlineReleasesAllSlotsAndLateBodiesCannotPersist() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = Saves(directory.appendingPathComponent("config.json"))
        let server = LocalHTTPServer()
        defer { server.stop() }
        let port = try availablePort()
        try await start(server, port: port, saves: saves)
        var peers: [Peer] = []
        for _ in 0..<8 {
            let peer = try Peer(port: port)
            #expect(peer.send(prefix))
            peers.append(peer)
        }
        // Activity after three seconds must not reset the five-second deadline.
        try await Task.sleep(for: .seconds(3))
        for peer in peers { #expect(peer.send("{")) }
        for peer in peers {
            let expired = try #require(try peer.response(timeout: 3))
            #expect(expired.isEmpty)
            _ = peer.send("}")
        }
        #expect(saves.count == 0)
        #expect(!FileManager.default.fileExists(atPath: saves.url.path))
        // Refill every slot after expiry to verify capacity was actually released.
        var fresh: [Peer] = []
        for _ in 0..<8 {
            let peer = try Peer(port: port)
            #expect(peer.send(prefix + "{"))
            fresh.append(peer)
        }
        for peer in fresh { #expect(peer.send("}")) }
        for peer in fresh {
            let response = try #require(try peer.response(timeout: 2))
            #expect(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 200 "))
        }
        #expect(saves.count == 8)
        #expect(try Data(contentsOf: saves.url) == Data("{}".utf8))
    }
}
