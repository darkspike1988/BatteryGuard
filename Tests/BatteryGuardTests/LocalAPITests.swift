import Foundation
import Darwin
import Testing
import BatteryGuardShared
@testable import BatteryGuard

@MainActor
struct LocalAPITests {
    @MainActor struct Fixture {
        let directory: URL
        let config: ConfigStore
        let status: StatusStore
        let api: LocalAPIStore
        let credentials: APITokenStore
        let token: String
        func cleanUp() { api.stop(); try? FileManager.default.removeItem(at: directory) }
        func request(_ path: String, method: String = "GET", json: String? = nil,
                     overrides: [String: String] = [:]) -> LocalHTTPRequest {
            var headers = ["host": "127.0.0.1:\(api.port)", "authorization": "Bearer " + token]
            if json != nil { headers["content-type"] = "application/json" }
            headers.merge(overrides) { _, new in new }
            return LocalHTTPRequest(method: method, target: path, headers: headers, body: Data((json ?? "").utf8))
        }
    }
    func fixture(port: UInt16? = nil) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let configURL = directory.appendingPathComponent("config.json")
        try BGJSON.encoder().encode(BGConfig()).write(to: configURL)
        let config = ConfigStore(configURL: configURL)
        let status = StatusStore(startImmediately: false, reader: { nil })
        var current = BGStatus(); current.daemonVersion = AppVersion.requiredDaemon; current.updatedAt = Date()
        status.status = current; status.isDaemonActive = true
        let preferences = UserDefaults(suiteName: "LocalAPITests.\(UUID().uuidString)")!
        let credentials = APITokenStore(url: directory.appendingPathComponent("api-token"))
        let token = try credentials.loadOrCreate()
        let api = LocalAPIStore(config: config, status: status, history: HistoryStore(preview: true),
            preferences: preferences, credentials: credentials, port: port ?? UInt16.random(in: 40_000...60_000))
        api.setEnabled(true)
        return Fixture(directory: directory, config: config, status: status, api: api, credentials: credentials, token: token)
    }

    @Test func authenticationOriginAndHostAreRequiredAndRotationRevokesOldToken() throws {
        let f = try fixture(); defer { f.cleanUp() }
        #expect(f.api.respond(to: f.request("/api/v1/status")).status == 200)
        #expect(f.api.respond(to: f.request("/api/v1/status", overrides: ["authorization": "Bearer wrong"])).status == 401)
        #expect(f.api.respond(to: f.request("/api/v1/status", overrides: ["origin": "https://example.com"])).status == 403)
        #expect(f.api.respond(to: f.request("/api/v1/status", overrides: ["host": "localhost:\(f.api.port)"])).status == 403)
        f.api.rotateToken()
        #expect(f.api.respond(to: f.request("/api/v1/status")).status == 401)
        let newToken = try f.credentials.loadOrCreate()
        #expect(newToken != f.token)
        #expect(f.api.respond(to: f.request("/api/v1/status", overrides: ["authorization": "Bearer " + newToken])).status == 200)
        f.api.setEnabled(false)
        #expect(f.api.respond(to: f.request("/api/v1/status")).status == 503)
    }

    @Test func configReturnsSavedStateEvenWithPendingUIChanges() throws {
        let f = try fixture(); defer { f.cleanUp() }
        f.config.config.upperLimit = 90
        let response = f.api.respond(to: f.request("/api/v1/config"))
        #expect(response.status == 200)
        #expect(try BGJSON.decoder().decode(BGConfig.self, from: response.jsonData).upperLimit == 80)
        f.api.allowsControl = true
        #expect(f.api.respond(to: f.request("/api/v1/actions", method: "POST", json: #"{"action":"profile","profile":"desk"}"#)).status == 409)
        f.config.flushPendingSave()
    }

    @Test func diagnosticReportIsAuthenticatedReadOnlyAndRedacted() throws {
        let f = try fixture(); defer { f.cleanUp() }
        let secret = "secret-token-/Users/Alice"
        f.status.status.message = secret
        f.status.status.configurationNotice = secret
        let original = f.config.config
        let response = f.api.respond(to: f.request("/api/v1/diagnostics"))
        #expect(response.status == 200)
        let report = try BGJSON.decoder().decode(BGDiagnosticReport.self, from: response.jsonData)
        #expect(report.schemaVersion == 1 && report.system == nil)
        #expect(!String(decoding: response.jsonData, as: UTF8.self).contains(secret))
        #expect(f.api.respond(to: f.request("/api/v1/diagnostics", overrides: ["authorization": "Bearer wrong"])).status == 401)
        #expect(f.api.respond(to: f.request("/api/v1/diagnostics", method: "POST")).status == 405)
        #expect(f.api.respond(to: f.request("/api/v1/diagnostics?other=1")).status == 400)
        #expect(f.config.config == original && !f.config.hasUnsavedChanges)
    }

    @Test func actionsRequireOptInAndConfirmedSave() throws {
        let f = try fixture(); defer { f.cleanUp() }
        let action = f.request("/api/v1/actions", method: "POST", json: #"{"action":"profile","profile":"desk"}"#)
        #expect(f.api.respond(to: action).status == 403)
        f.api.allowsControl = true
        let response = f.api.respond(to: action)
        #expect(response.status == 200)
        let body = try JSONSerialization.jsonObject(with: response.jsonData) as! [String: Any]
        #expect(body["hardwareApplied"] as? Bool == false)
        #expect((body["savedConfig"] as? [String: Any])?["upperLimit"] as? Int == 60)
        #expect(f.config.config.upperLimit == 60)
        try FileManager.default.removeItem(at: f.directory.appendingPathComponent("config.json"))
        #expect(f.api.respond(to: action).status == 503)
        #expect(f.config.config.upperLimit == 60 && !f.config.hasUnsavedChanges)
    }

    @Test func invalidActionsStaleDaemonAndNativeModeDoNotMutate() throws {
        let f = try fixture(); defer { f.cleanUp() }
        f.api.allowsControl = true
        for json in [#"{"action":"pause","minutes":0}"#, #"{"action":"pause","minutes":5,"unknown":true}"#, "broken"] {
            #expect(f.api.respond(to: f.request("/api/v1/actions", method: "POST", json: json)).status == 400)
        }
        #expect(f.config.config.pauseUntil == nil)
        f.status.status.updatedAt = Date().addingTimeInterval(-61)
        #expect(f.api.respond(to: f.request("/api/v1/actions", method: "POST", json: #"{"action":"pause","minutes":5}"#)).status == 503)
        f.status.status.updatedAt = Date()
        let url = f.directory.appendingPathComponent("config.json")
        try BGConfigFile.update(at: url) { $0.mode = .native }
        #expect(f.api.respond(to: f.request("/api/v1/actions", method: "POST", json: #"{"action":"full-charge"}"#)).status == 409)
        #expect(try BGConfigFile.read(at: url).mode == .native)
    }

    @Test func historyQueryCSVAndRoutingAreBounded() throws {
        let f = try fixture(); defer { f.cleanUp() }
        for query in ["hours", "hours=", "hours=0", "hours=169", "hours=-1", "hours=1.5", "hours=1&hours=2", "other=1"] {
            #expect(f.api.respond(to: f.request("/api/v1/history?" + query)).status == 400)
        }
        let samples = f.api.respond(to: f.request("/api/v1/history?hours=24"))
        #expect(samples.status == 200)
        #expect(try BGJSON.decoder().decode([BGHistorySample].self, from: samples.jsonData).count == 240)
        let csv = f.api.respond(to: f.request("/api/v1/history.csv?hours=168"))
        #expect(csv.contentType == "text/csv; charset=utf-8")
        #expect(String(data: csv.jsonData, encoding: .utf8)?.hasPrefix("timestamp,percent,") == true)
        #expect(f.api.respond(to: f.request("/api/v1/config", method: "POST")).status == 405)
        #expect(f.api.respond(to: f.request("/api/v1/nope")).status == 404)
        #expect(f.api.respond(to: f.request("/api/v1/%73tatus")).status == 400)
    }

    @Test func tokenPersistencePermissionsAndUnsafePaths() throws {
        let f = try fixture(); defer { f.cleanUp() }
        #expect(APITokenStore.isValid(f.token))
        #expect(try f.credentials.loadOrCreate() == f.token)
        let mode = try FileManager.default.attributesOfItem(atPath: f.credentials.url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let target = f.directory.appendingPathComponent("target")
        try FileManager.default.moveItem(at: f.credentials.url, to: target)
        try FileManager.default.createSymbolicLink(atPath: f.credentials.url.path, withDestinationPath: target.path)
        #expect(throws: (any Error).self) { try f.credentials.loadOrCreate() }
        #expect(try String(contentsOf: target, encoding: .utf8) == f.token)
    }

    @Test func realLoopbackHTTPReadAndActionStayInsideTemporaryConfiguration() async throws {
        let f = try fixture(); defer { f.cleanUp() }
        let deadline = Date().addingTimeInterval(3)
        while !f.api.running && !f.api.isError && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(f.api.running)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: f.api.address + "/status")!)
        request.timeoutInterval = 3
        request.setValue("Bearer " + f.token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["daemonActive"] as? Bool == true)
        request.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, rejected) = try await session.data(for: request)
        #expect((rejected as? HTTPURLResponse)?.statusCode == 401)
        f.api.allowsControl = true
        request.url = URL(string: f.api.address + "/actions")!
        request.httpMethod = "POST"
        request.setValue("Bearer " + f.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"action":"profile","profile":"desk"}"#.utf8)
        let (_, saved) = try await session.data(for: request)
        #expect((saved as? HTTPURLResponse)?.statusCode == 200)
        #expect(try BGConfigFile.read(at: f.directory.appendingPathComponent("config.json")).upperLimit == 60)
    }

    @Test func occupiedLoopbackPortReportsFailureAndCanBeRetried() async throws {
        // Reserve an OS-selected loopback port, avoiding races with random port selection.
        var descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { if descriptor >= 0 { _ = close(descriptor) } }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else { throw POSIXError(.EIO) }
        var addressSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &addressSize)
            }
        }
        guard named == 0 else { throw POSIXError(.EIO) }
        let f = try fixture(port: UInt16(bigEndian: address.sin_port))
        defer { f.cleanUp() }
        let failureDeadline = ProcessInfo.processInfo.systemUptime + 3
        while !f.api.isError && ProcessInfo.processInfo.systemUptime < failureDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(f.api.isError)
        #expect(!f.api.running)
        #expect(f.api.message?.contains("API konnte nicht gestartet werden") == true)
        _ = close(descriptor)
        descriptor = -1
        f.api.setEnabled(true)
        let readyDeadline = ProcessInfo.processInfo.systemUptime + 3
        while !f.api.running && !f.api.isError && ProcessInfo.processInfo.systemUptime < readyDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(f.api.running)
        #expect(!f.api.isError)
    }

    @Test func actionsContentTypeValidationAcceptsUTF8VariantsAndRejectsInvalidTypes() throws {
        let f = try fixture(); defer { f.cleanUp() }
        f.api.allowsControl = true
        let validPayload = #"{"action":"profile","profile":"desk"}"#

        let acceptedContentTypes = [
            "application/json",
            "APPLICATION/JSON",
            "Application/Json",
            "application/json; charset=utf-8",
            "application/json; charset=UTF-8",
            "application/json; charset=Utf-8",
            "application/json;charset=utf-8",
            "application/json; charset=\"utf-8\"",
            "application/json; charset=\"UTF-8\"",
            "application/json;charset=\"utf-8\"",
            "application/json ; charset = utf-8",
            "application/json ; charset = \"utf-8\"",
            " application/json; charset=utf-8 ",
            "Application/Json; Charset=\"utf-8\""
        ]

        for contentType in acceptedContentTypes {
            let request = f.request(
                "/api/v1/actions",
                method: "POST",
                json: validPayload,
                overrides: ["content-type": contentType]
            )
            let response = f.api.respond(to: request)
            #expect(response.status == 200, "Content-Type '\(contentType)' sollte akzeptiert werden.")
        }

        let initialConfig = f.config.config

        let rejectedContentTypes = [
            // Fremde Medientypen
            "text/plain",
            "application/xml",
            "text/json",
            "text/html",
            "application/x-www-form-urlencoded",
            "multipart/form-data",
            "image/png",
            "text/plain; charset=utf-8",

            // Fremde / ungültige Charsets
            "application/json; charset=latin1",
            "application/json; charset=latin-1",
            "application/json; charset=\"latin1\"",
            "application/json; charset=iso-8859-1",
            "application/json; charset=utf-16",
            "application/json; charset=us-ascii",
            "application/json; charset=utf8",

            // Doppelte Parameter
            "application/json; charset=utf-8; charset=utf-8",
            "application/json; charset=utf-8; charset=UTF-8",
            "application/json; charset=\"utf-8\"; charset=\"utf-8\"",

            // Unbekannte Parameter
            "application/json; foo=bar",
            "application/json; boundary=something",
            "application/json; charset=utf-8; foo=bar",
            "application/json; foo=bar; charset=utf-8",
            "application/json; profile=desk",

            "application/json; charset=\" utf-8 \"",

            // Kaputte Parameter
            "application/json;",
            "application/json; ",
            "application/json; charset=utf-8;",
            "application/json;;charset=utf-8",
            "application/json; ; charset=utf-8",
            "application/json; charset",
            "application/json; charset=",
            "application/json; charset= ",
            "application/json; =utf-8",
            "application/json; =",
            "application/json; charset=\"utf-8",
            "application/json; charset=utf-8\"",
            "application/json; charset=\"\"",
            "application/json; charset=\"   \"",
            "application/json; charset=\"\"utf-8\"\"",
            "application/json; charset=\"utf-8\"extra",
            "application/json; charset=utf-8=extra",
            "; charset=utf-8",
            "charset=utf-8",
            ""
        ]

        for contentType in rejectedContentTypes {
            let request = f.request(
                "/api/v1/actions",
                method: "POST",
                json: validPayload,
                overrides: ["content-type": contentType]
            )
            let response = f.api.respond(to: request)
            #expect(response.status == 400, "Content-Type '\(contentType)' sollte abgelehnt werden.")
            let body = (try? JSONSerialization.jsonObject(with: response.jsonData)) as? [String: Any]
            #expect(body?["error"] as? String == "invalid_content_type")
        }

        let missingContentTypeRequest = LocalHTTPRequest(
            method: "POST",
            target: "/api/v1/actions",
            headers: ["host": "127.0.0.1:\(f.api.port)", "authorization": "Bearer " + f.token],
            body: Data(validPayload.utf8)
        )
        let missingResponse = f.api.respond(to: missingContentTypeRequest)
        #expect(missingResponse.status == 400)
        let missingBody = (try? JSONSerialization.jsonObject(with: missingResponse.jsonData)) as? [String: Any]
        #expect(missingBody?["error"] as? String == "invalid_content_type")

        #expect(f.config.config.upperLimit == initialConfig.upperLimit)
    }
}
