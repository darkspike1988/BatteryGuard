import Foundation
import Observation
import CryptoKit
import AppKit
import UserNotifications

/// App-only releases do not require reinstalling an unchanged root service.
enum AppVersion {
    static let current = "0.2.3"
    static let requiredDaemon = "0.2.2"
    static var installed: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? current
    }
}

struct ReleaseVersion: Equatable, Comparable, Sendable {
    let components: [Int]
    init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browser_download_url: URL
        let size: Int
        let digest: String?
    }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    var dmg: Asset? { assets.first { $0.name == "B-Guard.dmg" } }
    var releaseURL: URL? {
        guard ReleaseVersion(tag_name) != nil else { return nil }
        return URL(string: "https://github.com/darkspike1988/BatteryGuard/releases/tag/\(tag_name)")
    }
    var safeDownload: Asset? {
        guard !draft, !prerelease, ReleaseVersion(tag_name) != nil, let asset = dmg,
              asset.size > 0, asset.size <= 100_000_000,
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.port == nil || asset.browser_download_url.port == 443,
              asset.browser_download_url.user == nil,
              asset.browser_download_url.password == nil,
              asset.browser_download_url.query == nil,
              asset.browser_download_url.fragment == nil,
              asset.browser_download_url.path == "/darkspike1988/BatteryGuard/releases/download/\(tag_name)/B-Guard.dmg",
              let digest = asset.digest, digest.hasPrefix("sha256:"),
              digest.count == 71,
              digest.dropFirst(7).allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { return nil }
        return asset
    }
}

enum UpdateError: LocalizedError {
    case server(Int), invalidRelease, invalidDownload, checksum
    var errorDescription: String? {
        switch self {
        case .server(403), .server(429): "GitHub begrenzt gerade die Anfragen. Bitte später erneut versuchen."
        case .server(let code): "GitHub ist nicht erreichbar (HTTP \(code))."
        case .invalidRelease: "Die veröffentlichte Version konnte nicht zuverlässig erkannt werden."
        case .invalidDownload: "Kein verifizierbarer DMG-Download vorhanden. Bitte die GitHub-Veröffentlichung prüfen."
        case .checksum: "Die Prüfsumme stimmt nicht. Der Download wurde verworfen und nicht geöffnet."
        }
    }
}

@MainActor
@Observable
final class UpdateStore {
    var isChecking = false
    var isDownloading = false
    var release: GitHubRelease?
    var message: String?
    var isError = false
    var checkedAt: Date?
    var downloadedURL: URL?
    var automaticChecksEnabled: Bool {
        didSet {
            preferences.set(automaticChecksEnabled, forKey: "bg.autoUpdateChecks")
            if isMonitoring { restartMonitoring() }
        }
    }
    private let preferences: UserDefaults
    private var monitoringTask: Task<Void, Never>?
    private var isMonitoring = false
    private let installedVersion: String
    private let fetch: @Sendable () async throws -> Data

    init(installedVersion: String = AppVersion.installed, preferences: UserDefaults = .standard,
         fetch: @escaping @Sendable () async throws -> Data = UpdateStore.fetchLatest) {
        self.installedVersion = installedVersion
        self.preferences = preferences
        self.automaticChecksEnabled = preferences.object(forKey: "bg.autoUpdateChecks") as? Bool ?? true
        self.fetch = fetch
        if let data = preferences.data(forKey: "bg.cachedRelease"),
           let cached = try? JSONDecoder().decode(GitHubRelease.self, from: data),
           !cached.draft, !cached.prerelease, ReleaseVersion(cached.tag_name) != nil {
            release = cached
            checkedAt = preferences.object(forKey: "bg.lastSuccessfulUpdateCheck") as? Date
        }
    }
    var currentVersion: String { installedVersion }
    var updateAvailable: Bool {
        guard let release, let latest = ReleaseVersion(release.tag_name),
              let installed = ReleaseVersion(installedVersion) else { return false }
        return latest > installed
    }

    nonisolated static func fetchLatest() async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/darkspike1988/BatteryGuard/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("B-Guard-Update-Check", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidRelease }
        guard response.statusCode == 200 else { throw UpdateError.server(response.statusCode) }
        guard data.count <= 1_000_000 else { throw UpdateError.invalidRelease }
        return data
    }

    func check() async {
        guard !isChecking, !isDownloading else { return }
        isChecking = true
        isError = false
        message = nil
        defer { isChecking = false }
        do {
            preferences.set(Date(), forKey: "bg.lastUpdateAttempt")
            let data = try await fetch()
            guard data.count <= 1_000_000 else { throw UpdateError.invalidRelease }
            let result = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !result.draft, !result.prerelease, ReleaseVersion(result.tag_name) != nil else {
                throw UpdateError.invalidRelease
            }
            release = result
            checkedAt = Date()
            preferences.set(data, forKey: "bg.cachedRelease")
            preferences.set(checkedAt, forKey: "bg.lastSuccessfulUpdateCheck")
            message = updateAvailable ? "B-Guard \(result.version) ist verfügbar."
                : "Du verwendest die aktuelle oder eine neuere Version."
        } catch {
            isError = true
            message = "Updateprüfung fehlgeschlagen. " + error.localizedDescription
        }
    }

    func startAutomaticChecks() {
        isMonitoring = true
        restartMonitoring()
    }

    func stopAutomaticChecks() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func restartMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        guard automaticChecksEnabled else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfNeeded()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    func checkIfNeeded(now: Date = Date()) async {
        guard automaticChecksEnabled, !isChecking, !isDownloading else { return }
        if let last = preferences.object(forKey: "bg.lastUpdateAttempt") as? Date {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 0 && elapsed < 24 * 3600 { return }
        }
        await check()
        guard !isError, updateAvailable, let release,
              preferences.string(forKey: "bg.notifiedUpdateVersion") != release.version,
              Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "B-Guard \(release.version) ist verfügbar"
        content.body = "Neue Änderungen und Verbesserungen warten. Öffne Updates & Neuigkeiten in B-Guard."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "bg.update.\(release.version)", content: content, trigger: nil))
            preferences.set(release.version, forKey: "bg.notifiedUpdateVersion")
        } catch { /* The in-app notice remains visible when notifications fail. */ }
    }

    nonisolated static func verify(_ data: Data, asset: GitHubRelease.Asset) throws {
        guard data.count == asset.size, let digest = asset.digest else { throw UpdateError.checksum }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard "sha256:" + actual == digest.lowercased() else { throw UpdateError.checksum }
    }

    func downloadAndOpen() async {
        guard !isChecking, !isDownloading, updateAvailable, let release else { return }
        guard let asset = release.safeDownload else {
            isError = true; message = UpdateError.invalidDownload.localizedDescription; return
        }
        isDownloading = true
        isError = false
        message = "Update wird geladen und geprüft …"
        defer { isDownloading = false }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (temporary, response) = try await session.download(from: asset.browser_download_url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw UpdateError.invalidDownload
            }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size == asset.size else { throw UpdateError.checksum }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            try Self.verify(data, asset: asset)
            let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("B-Guard-\(release.version)-\(UUID().uuidString.prefix(8)).dmg")
            try FileManager.default.moveItem(at: temporary, to: destination)
            downloadedURL = destination
            if NSWorkspace.shared.open(destination) {
                message = "Download geprüft und geöffnet. B-Guard beenden und die neue App auf Programme ziehen."
            } else {
                message = "Download geprüft. Öffne die DMG im Downloads-Ordner und ersetze B-Guard in Programme."
            }
        } catch {
            isError = true
            message = "Update konnte nicht geladen werden. " + error.localizedDescription
        }
    }
}
