import Foundation
import Observation
import AppKit
import BatteryGuardShared

@MainActor
@Observable
final class LocalAPIStore {
    private(set) var enabled: Bool
    var allowsControl: Bool {
        didSet { preferences.set(allowsControl, forKey: "bg.restAPIControl") }
    }
    private(set) var running = false
    private(set) var message: String?
    private(set) var isError = false
    let port: UInt16
    var address: String { "http://127.0.0.1:\(port)/api/v1" }
    private let preferences: UserDefaults
    private let credentials: APITokenStore
    private var token: String?
    private var listenerID: UUID?
    private let server = LocalHTTPServer()
    private let config: ConfigStore
    private let status: StatusStore
    private let history: HistoryStore

    init(config: ConfigStore, status: StatusStore, history: HistoryStore,
         preferences: UserDefaults = .standard, credentials: APITokenStore = APITokenStore(), port: UInt16 = 8767) {
        self.config = config; self.status = status; self.history = history
        self.preferences = preferences; self.credentials = credentials; self.port = port
        enabled = preferences.bool(forKey: "bg.restAPIEnabled")
        allowsControl = preferences.bool(forKey: "bg.restAPIControl")
    }

    func startIfEnabled() { if enabled { setEnabled(true) } }

    func setEnabled(_ value: Bool) {
        server.stop()
        listenerID = nil
        running = false
        enabled = value
        preferences.set(value, forKey: "bg.restAPIEnabled")
        isError = false
        message = nil
        guard value else { token = nil; return }
        do {
            token = try credentials.loadOrCreate()
            let id = UUID()
            listenerID = id
            try server.start(port: port, onReady: { [weak self] in
                Task { @MainActor in
                    guard let self, self.listenerID == id else { return }
                    self.running = true
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor in
                    guard let self, self.listenerID == id else { return }
                    self.running = false
                    self.isError = true
                    self.message = "API konnte nicht gestartet werden. " + error
                }
            }) { [weak self] request in
                guard let self else { return Self.failure(503, "api_unavailable", "API nicht verfügbar.") }
                return await self.respond(to: request)
            }
        } catch {
            isError = true
            message = "API konnte nicht gestartet werden. " + error.localizedDescription
        }
    }

    func stop() { listenerID = nil; server.stop(); running = false }

    func copyToken() {
        guard enabled, let token else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        message = "API-Token kopiert. Behandle ihn wie ein Passwort."
    }

    func rotateToken() {
        do {
            token = try credentials.rotate()
            isError = false
            message = "Neuer API-Token erstellt. Der bisherige Token ist ungültig."
        } catch {
            isError = true
            message = "Token konnte nicht erneuert werden. " + error.localizedDescription
        }
    }

    nonisolated private static func failure(_ code: Int, _ error: String, _ description: String) -> LocalHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: ["error": error, "message": description])) ?? Data()
        return LocalHTTPResponse(status: code, jsonData: data)
    }

    nonisolated static func isValidJSONContentType(_ rawHeader: String?) -> Bool {
        guard let rawHeader else { return false }
        let trimmedHeader = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHeader.isEmpty else { return false }

        let parts = trimmedHeader.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return false }

        let mediaType = parts[0].trimmingCharacters(in: .whitespaces)
        guard mediaType.caseInsensitiveCompare("application/json") == .orderedSame else {
            return false
        }

        if parts.count == 1 {
            return true
        }

        let param = parts[1].trimmingCharacters(in: .whitespaces)
        guard !param.isEmpty else { return false }

        let keyValue = param.split(separator: "=", omittingEmptySubsequences: false)
        guard keyValue.count == 2 else { return false }

        let key = keyValue[0].trimmingCharacters(in: .whitespaces)
        guard key.caseInsensitiveCompare("charset") == .orderedSame else { return false }

        let rawValue = keyValue[1].trimmingCharacters(in: .whitespaces)
        guard !rawValue.isEmpty else { return false }

        let charsetValue: String
        if rawValue.hasPrefix("\"") {
            guard rawValue.count >= 2, rawValue.hasSuffix("\"") else { return false }
            let inner = rawValue.dropFirst().dropLast()
            guard !inner.contains("\"") else { return false }
            charsetValue = String(inner)
        } else {
            guard !rawValue.contains("\"") else { return false }
            charsetValue = rawValue
        }

        return charsetValue.caseInsensitiveCompare("utf-8") == .orderedSame
    }

    private func json<T: Encodable>(_ value: T) throws -> LocalHTTPResponse {
        LocalHTTPResponse(status: 200, jsonData: try BGJSON.encoder().encode(value))
    }

    func respond(to request: LocalHTTPRequest, now: Date = Date()) -> LocalHTTPResponse {
        guard !Task.isCancelled else { return Self.failure(503, "request_cancelled", "Anfrage abgebrochen.") }
        guard enabled, let token else { return Self.failure(503, "api_disabled", "API ist ausgeschaltet.") }
        guard request.headers["origin"] == nil,
              request.headers["host"] == "127.0.0.1:\(port)" else {
            return Self.failure(403, "local_requests_only", "Nur direkte lokale API-Anfragen sind erlaubt.")
        }
        guard APITokenStore.matchesAuthorization(request.headers["authorization"], token: token) else {
            return Self.failure(401, "unauthorized", "Gültiger Bearer-Token erforderlich.")
        }
        guard let components = URLComponents(string: request.target), components.scheme == nil,
              components.host == nil, components.fragment == nil,
              components.percentEncodedPath == components.path else {
            return Self.failure(400, "invalid_path", "Ungültiger API-Pfad.")
        }
        let path = components.path
        let reads = ["/api/v1/status", "/api/v1/config", "/api/v1/history", "/api/v1/history.csv", "/api/v1/capabilities", "/api/v1/power-flow"]
        guard reads.contains(path) || path == "/api/v1/actions" else { return Self.failure(404, "not_found", "Endpunkt nicht vorhanden.") }
        guard request.method == (path == "/api/v1/actions" ? "POST" : "GET") else {
            return Self.failure(405, "method_not_allowed", "Methode für diesen Endpunkt nicht erlaubt.")
        }
        do {
            let age = now.timeIntervalSince(status.status.updatedAt)
            let daemonActive = status.isDaemonActive && age >= -5 && age <= 60
            if path.hasPrefix("/api/v1/history") {
                let items = components.queryItems ?? []
                guard items.allSatisfy({ $0.name == "hours" }), items.count <= 1 else {
                    return Self.failure(400, "invalid_query", "Nur hours=1…168 ist erlaubt.")
                }
                let raw = items.isEmpty ? "24" : (items.first?.value ?? "")
                guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                      let hours = Int(raw), (1...168).contains(hours), request.body.isEmpty else {
                    return Self.failure(400, "invalid_query", "hours muss eine ganze Zahl von 1 bis 168 sein.")
                }
                let samples = history.samples.filter { $0.timestamp >= now.addingTimeInterval(-Double(hours) * 3600) && $0.timestamp <= now.addingTimeInterval(5) }
                if path.hasSuffix(".csv") {
                    return LocalHTTPResponse(status: 200, jsonData: Data(BGHistory.csv(samples).utf8), contentType: "text/csv; charset=utf-8")
                }
                return try json(samples)
            }
            guard components.query == nil else { return Self.failure(400, "invalid_query", "Dieser Endpunkt akzeptiert keine Query-Parameter.") }
            if path != "/api/v1/actions", !request.body.isEmpty { return Self.failure(400, "unexpected_body", "GET-Anfragen benötigen keinen Body.") }
            switch path {
            case "/api/v1/status":
                struct Result: Encodable { let daemonActive: Bool; let status: BGStatus }
                return try json(Result(daemonActive: daemonActive, status: status.status))
            case "/api/v1/config":
                do { return try json(config.savedConfig()) }
                catch { return Self.failure(503, "config_unavailable", "Gespeicherte Einstellungen sind nicht verfügbar.") }
            case "/api/v1/capabilities":
                let value: [String: Any] = ["apiVersion": "1", "appVersion": AppVersion.installed,
                    "requiredDaemon": AppVersion.requiredDaemon, "daemonActive": daemonActive,
                    "controlAllowed": allowsControl, "controlReady": daemonActive && !status.daemonNeedsUpdate,
                    "availableProfiles": BGProfile.allCases.map(\.rawValue), "historyRetentionHours": 168,
                    "smcKeysDetected": status.status.smcKeysDetected,
                    "usesNativeDesktopFallback": status.status.usesNativeDesktopFallback]
                return LocalHTTPResponse(status: 200, jsonData: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
            case "/api/v1/power-flow":
                // Freshness represents collection freshness (when the sample was gathered by B-Guard),
                // not sensor freshness (the underlying hardware sensor update interval).
                let sample = status.powerFlow
                let isFresh = sample?.isFresh(at: now) ?? false
                let hasBatteryOrInput = (sample?.batteryWatts != nil) || (sample?.inputWatts != nil)
                let available = isFresh && hasBatteryOrInput

                struct PowerFlowResponse: Encodable {
                    let available: Bool
                    let fresh: Bool
                    let sampledAt: Date?
                    let source: String?
                    let inputWatts: Double?
                    let batteryWatts: Double?
                    let systemWatts: Double?
                    let adapterRatedWatts: Double?
                    let hardwarePercent: Double?
                }

                if !available {
                    // No usable current power: omit all values.
                    return try json(PowerFlowResponse(
                        available: false,
                        fresh: isFresh,
                        sampledAt: nil,
                        source: nil,
                        inputWatts: nil,
                        batteryWatts: nil,
                        systemWatts: nil,
                        adapterRatedWatts: nil,
                        hardwarePercent: nil
                    ))
                }

                return try json(PowerFlowResponse(
                    available: available,
                    fresh: true,
                    sampledAt: sample?.sampledAt,
                    source: sample?.source,
                    inputWatts: sample?.inputWatts,
                    batteryWatts: sample?.batteryWatts,
                    systemWatts: sample?.systemWatts,
                    adapterRatedWatts: sample?.adapterRatedWatts,
                    hardwarePercent: sample?.hardwarePercent
                ))
            default:
                guard allowsControl else { return Self.failure(403, "read_only", "API-Steuerung ist nicht freigegeben.") }
                guard daemonActive, !status.daemonNeedsUpdate else {
                    return Self.failure(503, "daemon_unavailable", "Aktuellen Hintergrunddienst starten oder aktualisieren.")
                }
                guard Self.isValidJSONContentType(request.headers["content-type"]) else {
                    return Self.failure(400, "invalid_content_type", "Content-Type application/json erforderlich.")
                }
                let action = try BGJSON.decoder().decode(BGChargingActionRequest.self, from: request.body)
                let saved = try config.performAPIAction(action, at: now)
                struct Result: Encodable { let savedConfig: BGConfig; let hardwareApplied: Bool }
                return try json(Result(savedConfig: saved, hardwareApplied: false))
            }
        } catch AppActionError.unsavedChanges {
            return Self.failure(409, "unsaved_ui_changes", "Zuerst die offenen Änderungen in B-Guard speichern.")
        } catch BGChargingActionError.unsupportedMode {
            return Self.failure(409, "unsupported_mode", "Zuerst ein Profil oder die Schutzsteuerung aktivieren.")
        } catch is DecodingError {
            return Self.failure(400, "invalid_action", "Ungültige JSON-Aktion oder Parameter.")
        } catch let error as BGChargingActionError {
            return Self.failure(400, "invalid_action", error.localizedDescription)
        } catch {
            return Self.failure(503, "save_failed", "Einstellungen konnten nicht bestätigt werden. " + error.localizedDescription)
        }
    }
}
