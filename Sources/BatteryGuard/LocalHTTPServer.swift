import Foundation
import Network

struct LocalHTTPRequest: Sendable, Equatable {
    let method: String
    let target: String
    /// Header names are lowercase; ambiguous duplicate headers are rejected.
    let headers: [String: String]
    let body: Data
}

struct LocalHTTPResponse: Sendable {
    let status: Int
    let jsonData: Data
    let contentType: String

    init(status: Int = 200, jsonData: Data, contentType: String = "application/json; charset=utf-8") {
        self.status = status
        self.jsonData = jsonData
        self.contentType = contentType
    }
}

struct LocalHTTPError: Error, Sendable {
    let status: Int
    let message: String
}

/// A deliberately small HTTP/1.1 subset: one GET/POST request, a known byte
/// length and no connection reuse. Routing/authentication belong to the caller.
enum LocalHTTPParser {
    static let maximumRequestBytes = 65_536
    static let maximumBodyBytes = 16_384
    static let maximumHeaderBytes = 16_384
    private static let delimiter = Data([13, 10, 13, 10])

    static func parse(_ data: Data) throws -> LocalHTTPRequest? {
        guard data.count <= maximumRequestBytes else {
            throw LocalHTTPError(status: 413, message: "Request too large")
        }
        guard let boundary = data.range(of: delimiter) else {
            guard data.count <= maximumHeaderBytes else {
                throw LocalHTTPError(status: 431, message: "Headers too large")
            }
            return nil
        }
        let headerData = data[..<boundary.lowerBound]
        guard headerData.count <= maximumHeaderBytes else {
            throw LocalHTTPError(status: 431, message: "Headers too large")
        }
        guard headerData.allSatisfy({ ($0 >= 32 && $0 <= 126) || $0 == 9 || $0 == 13 || $0 == 10 }),
              let text = String(data: headerData, encoding: .utf8) else {
            throw LocalHTTPError(status: 400, message: "Invalid headers")
        }
        let lines = text.components(separatedBy: "\r\n")
        let start = lines[0].components(separatedBy: " ")
        guard start.count == 3, start[2] == "HTTP/1.1", !start[1].isEmpty,
              start[1].utf8.count <= 2048, start[1].hasPrefix("/"),
              !start[1].contains("#"),
              start[1].utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw LocalHTTPError(status: 400, message: "Invalid request line")
        }
        guard start[0] == "GET" || start[0] == "POST" else {
            throw LocalHTTPError(status: 405, message: "Only GET and POST are supported")
        }
        guard lines.count <= 101 else { throw LocalHTTPError(status: 431, message: "Too many headers") }
        var headers: [String: String] = [:]
        let tokens = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                throw LocalHTTPError(status: 400, message: "Invalid header")
            }
            let name = String(line[..<colon])
            let rawValue = line[line.index(after: colon)...]
            guard !name.isEmpty, name.utf8.allSatisfy({ tokens.contains($0) }),
                  rawValue.utf8.allSatisfy({ ($0 >= 32 && $0 <= 126) || $0 == 9 }) else {
                throw LocalHTTPError(status: 400, message: "Invalid header")
            }
            let key = name.lowercased()
            guard headers[key] == nil else {
                throw LocalHTTPError(status: 400, message: "Duplicate header")
            }
            headers[key] = rawValue.trimmingCharacters(in: .whitespaces)
        }
        guard headers["host"]?.isEmpty == false else {
            throw LocalHTTPError(status: 400, message: "Host header required")
        }
        guard headers["transfer-encoding"] == nil else {
            throw LocalHTTPError(status: 400, message: "Transfer-Encoding is unsupported")
        }
        guard headers["expect"] == nil else {
            throw LocalHTTPError(status: 417, message: "Expect is unsupported")
        }
        let bodyLength: Int
        if let length = headers["content-length"] {
            guard !length.isEmpty, length.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let value = Int(length) else {
                throw LocalHTTPError(status: 400, message: "Invalid Content-Length")
            }
            guard value <= maximumBodyBytes else { throw LocalHTTPError(status: 413, message: "Body too large") }
            bodyLength = value
        } else { bodyLength = 0 }
        let expected = boundary.upperBound + bodyLength
        guard data.count <= expected else {
            throw LocalHTTPError(status: 400, message: "Trailing or pipelined data is unsupported")
        }
        guard data.count == expected else { return nil }
        return LocalHTTPRequest(method: start[0], target: start[1], headers: headers,
                                body: Data(data[boundary.upperBound..<expected]))
    }
}

/// App-local transport only. All mutable listener/connection state is confined
/// to one serial queue; lifecycle methods synchronize with that queue.
final class LocalHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (LocalHTTPRequest) async -> LocalHTTPResponse
    private let queue = DispatchQueue(label: "com.batteryguard.local-http", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var generation = UUID()
    private static let maximumConnections = 8

    private final class Client: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        var responding = false
        var timeout: DispatchWorkItem?
        var task: Task<Void, Never>?
        init(_ connection: NWConnection) { self.connection = connection }
    }

    init() { queue.setSpecific(key: queueKey, value: 1) }

    private func withQueue<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == 1 { return try operation() }
        return try queue.sync(execute: operation)
    }

    func start(port: UInt16 = 8767,
               onReady: (@Sendable () -> Void)? = nil,
               onFailure: (@Sendable (String) -> Void)? = nil,
               handler: @escaping Handler) throws {
        try withQueue {
            guard listener == nil else { throw LocalHTTPError(status: 409, message: "Server already running") }
            guard port != 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
                throw LocalHTTPError(status: 400, message: "Invalid port")
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: endpointPort)
            // Explicit host binding prevents wildcard/IPv6 external listeners.
            let created = try NWListener(using: parameters)
            let run = UUID()
            generation = run
            listener = created
            created.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.accept(connection, generation: run, handler: handler)
            }
            created.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == run else { return }
                if case .ready = state { onReady?() }
                if case .failed(let error) = state {
                    self.stopOnQueue(generation: run)
                    onFailure?(error.localizedDescription)
                }
            }
            created.start(queue: queue)
        }
    }

    func stop() { withQueue { stopOnQueue(generation: generation) } }

    private func stopOnQueue(generation run: UUID) {
        guard generation == run else { return }
        listener?.cancel()
        listener = nil
        for id in Array(clients.keys) { finish(id) }
        generation = UUID()
    }

    private func accept(_ connection: NWConnection, generation run: UUID, handler: @escaping Handler) {
        guard generation == run, listener != nil, clients.count < Self.maximumConnections else {
            connection.cancel()
            return
        }
        let id = UUID()
        let client = Client(connection)
        clients[id] = client
        let timeout = DispatchWorkItem { [weak self] in self?.finish(id) }
        client.timeout = timeout
        // Absolute monotonic timeout includes receipt, handler and response.
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.finish(id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(id, handler: handler)
    }

    private func receive(_ id: UUID, handler: @escaping Handler) {
        guard let client = clients[id], !client.responding else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, let active = self.clients[id], !active.responding else { return }
            if let data { active.buffer.append(data) }
            do {
                if let request = try LocalHTTPParser.parse(active.buffer) {
                    active.responding = true
                    active.buffer.removeAll(keepingCapacity: false)
                    active.task = Task { [weak self] in
                        let response = await handler(request)
                        guard !Task.isCancelled, let self else { return }
                        self.queue.async { [weak self] in self?.send(response, to: id) }
                    }
                } else if complete || error != nil {
                    self.send(Self.errorResponse(status: 400, message: "Incomplete request"), to: id)
                } else { self.receive(id, handler: handler) }
            } catch let error as LocalHTTPError {
                self.send(Self.errorResponse(status: error.status, message: error.message), to: id)
            } catch {
                self.send(Self.errorResponse(status: 400, message: "Invalid request"), to: id)
            }
        }
    }

    private func send(_ response: LocalHTTPResponse, to id: UUID) {
        guard let client = clients[id] else { return }
        client.responding = true
        let contentType = response.contentType.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 })
            ? response.contentType : "application/json; charset=utf-8"
        let reasons = [200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
                       403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict",
                       413: "Content Too Large", 417: "Expectation Failed", 431: "Request Header Fields Too Large",
                       500: "Internal Server Error", 503: "Service Unavailable"]
        let status = (100...599).contains(response.status) ? response.status : 500
        let header = "HTTP/1.1 \(status) \(reasons[status] ?? "Response")\r\nContent-Type: \(contentType)\r\nContent-Length: \(response.jsonData.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        var data = Data(header.utf8)
        data.append(response.jsonData)
        client.connection.send(content: data, completion: .contentProcessed { [weak self] _ in self?.finish(id) })
    }

    private func finish(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timeout?.cancel()
        client.task?.cancel()
        client.connection.cancel()
    }

    private static func errorResponse(status: Int, message: String) -> LocalHTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data("{}".utf8)
        return LocalHTTPResponse(status: status, jsonData: body)
    }
}
