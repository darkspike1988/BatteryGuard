import Foundation
import Darwin

/// No filenames, commands or arbitrary payloads cross the privileged boundary.
public struct BGConfigRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let baseline: BGConfig
    public let desired: BGConfig
    public let queryOnly: Bool?
    public let action: BGChargingActionRequest?

    public init(baseline: BGConfig, desired: BGConfig, queryOnly: Bool = false) {
        protocolVersion = 1
        self.baseline = baseline.sanitized()
        self.desired = desired.sanitized()
        self.queryOnly = queryOnly
        action = nil
    }

    /// Commands use v2 so older services must reject them, never merge a no-op.
    public init(action: BGChargingActionRequest) {
        protocolVersion = 2
        baseline = BGConfig()
        desired = BGConfig()
        queryOnly = false
        self.action = action
    }
}

public enum BGConfigActionFailure: String, Codable, Sendable {
    case invalidAction, unsupportedMode
}

public struct BGConfigResponse: Codable, Sendable {
    public let protocolVersion: Int
    public let config: BGConfig?
    public let error: String?
    public let actionFailure: BGConfigActionFailure?

    public init(config: BGConfig, protocolVersion: Int = 1) {
        self.protocolVersion = protocolVersion
        self.config = config.sanitized()
        error = nil
        actionFailure = nil
    }
    public init(error: String, actionFailure: BGConfigActionFailure? = nil, protocolVersion: Int = 1) {
        self.protocolVersion = protocolVersion
        config = nil
        self.error = error
        self.actionFailure = actionFailure
    }
}

public enum BGConfigIPCError: LocalizedError {
    case unavailable, timeout, invalidMessage, unauthorized, rejected(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Der sichere Einstellungsdienst ist nicht erreichbar. Bitte den B-Guard-Dienst unter Einstellungen aktualisieren oder einrichten."
        case .timeout: "Der Einstellungsdienst antwortet nicht rechtzeitig. Bitte erneut versuchen."
        case .invalidMessage: "Die Antwort des Einstellungsdienstes ist ungültig. Bitte den Dienst aktualisieren."
        case .unauthorized: "Nur der angemeldete Benutzer darf B-Guard-Einstellungen ändern."
        case .rejected(let reason): reason
        }
    }
}

public enum BGConfigPeerPolicy {
    public static func allows(peerUID: uid_t, consoleUID: uid_t?) -> Bool {
        peerUID == 0 || (consoleUID != nil && consoleUID != 0 && peerUID == consoleUID)
    }
}

/// One bounded frame per connection. Every wait shares an absolute deadline;
/// a peer sending one byte at a time cannot extend it indefinitely.
public enum BGConfigWire {
    public static let socketPath = BGPaths.directory + "/config.sock"
    public static let maximumBytes = 65_536
    public static let timeout: TimeInterval = 1

    public static func configure(_ descriptor: Int32) throws {
        guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw posixError() }
        var enabled: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                         socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw posixError() }
    }

    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [UInt8(0)]
        guard !path.utf8.contains(0), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw BGConfigIPCError.invalidMessage
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    public static func peerUID(_ descriptor: Int32) throws -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0 else { throw posixError() }
        return uid
    }

    public static func wait(_ descriptor: Int32, for events: Int16, until deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw BGConfigIPCError.timeout }
            var item = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&item, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
            if result < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if result == 0 { throw BGConfigIPCError.timeout }
            // POLLHUP can accompany readable final bytes. Read first in that case.
            if item.revents & events != 0 { return }
            throw BGConfigIPCError.invalidMessage
        }
    }

    public static func send<T: Encodable>(_ message: T, to descriptor: Int32, until deadline: TimeInterval) throws {
        let payload = try BGJSON.encoder().encode(message)
        guard !payload.isEmpty, payload.count <= maximumBytes else { throw BGConfigIPCError.invalidMessage }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try wait(descriptor, for: Int16(POLLOUT), until: deadline)
                let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    throw posixError()
                }
                guard count > 0 else { throw BGConfigIPCError.invalidMessage }
                offset += count
            }
        }
    }

    private static func read(_ count: Int, from descriptor: Int32, until deadline: TimeInterval) throws -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                try wait(descriptor, for: Int16(POLLIN), until: deadline)
                let received = recv(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if received < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    throw posixError()
                }
                guard received > 0 else { throw BGConfigIPCError.invalidMessage }
                offset += received
            }
        }
        return result
    }

    public static func receive<T: Decodable>(_ type: T.Type, from descriptor: Int32, until deadline: TimeInterval) throws -> T {
        let header = try read(4, from: descriptor, until: deadline)
        let count = header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard count > 0, count <= maximumBytes else { throw BGConfigIPCError.invalidMessage }
        let payload = try read(Int(count), from: descriptor, until: deadline)
        do { return try BGJSON.decoder().decode(type, from: payload) }
        catch { throw BGConfigIPCError.invalidMessage }
    }

    public static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

public enum BGConfigClient {
    public static func read() throws -> BGConfig {
        try exchange(BGConfigRequest(baseline: BGConfig(), desired: BGConfig(), queryOnly: true))
    }

    public static func update(baseline: BGConfig, desired: BGConfig) throws -> BGConfig {
        try exchange(BGConfigRequest(baseline: baseline, desired: desired))
    }

    public static func performAction(_ action: BGChargingActionRequest) throws -> BGConfig {
        try exchange(BGConfigRequest(action: action))
    }

    /// Explicit endpoint/UID parameters are for isolated socket tests; production uses root only.
    public static func exchange(_ request: BGConfigRequest,
                                socketPath: String = BGConfigWire.socketPath,
                                expectedServerUID: uid_t = 0) throws -> BGConfig {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BGConfigWire.posixError() }
        defer { _ = close(descriptor) }
        try BGConfigWire.configure(descriptor)
        let deadline = ProcessInfo.processInfo.systemUptime + BGConfigWire.timeout
        var address = try BGConfigWire.address(socketPath)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result < 0 {
            guard errno == EINPROGRESS else { throw BGConfigIPCError.unavailable }
            try BGConfigWire.wait(descriptor, for: Int16(POLLOUT), until: deadline)
            var connectionError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &connectionError, &length) == 0,
                  connectionError == 0 else { throw BGConfigIPCError.unavailable }
        }
        guard try BGConfigWire.peerUID(descriptor) == expectedServerUID else { throw BGConfigIPCError.unauthorized }
        try BGConfigWire.send(request, to: descriptor, until: deadline)
        let response = try BGConfigWire.receive(BGConfigResponse.self, from: descriptor, until: deadline)
        guard response.protocolVersion == request.protocolVersion else { throw BGConfigIPCError.invalidMessage }
        if let error = response.error {
            switch response.actionFailure {
            case .invalidAction: throw BGChargingActionError.invalidRequest(error)
            case .unsupportedMode: throw BGChargingActionError.unsupportedMode
            case nil: throw BGConfigIPCError.rejected(error)
            }
        }
        guard let config = response.config else { throw BGConfigIPCError.invalidMessage }
        return config.sanitized()
    }
}
