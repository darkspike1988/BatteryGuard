import Foundation
import Testing
import CryptoKit
@testable import BatteryGuard

@MainActor
struct UpdateTests {
    func preferences() -> UserDefaults {
        UserDefaults(suiteName: "BGuardUpdateTests.\(UUID().uuidString)")!
    }
    func fixture(version: String = "v0.3.0", url: String = "https://github.com/darkspike1988/BatteryGuard/releases/download/v0.3.0/B-Guard.dmg", digest: String? = nil) throws -> Data {
        let digest = digest ?? "sha256:" + String(repeating: "a", count: 64)
        return try JSONSerialization.data(withJSONObject: [
            "tag_name": version, "body": "Neue Änderungen und Verbesserungen.", "draft": false, "prerelease": false,
            "assets": [["name": "B-Guard.dmg", "browser_download_url": url, "size": 3, "digest": digest]]
        ])
    }

    @Test func numericVersionComparisonAndUnsafeVersions() {
        #expect(ReleaseVersion("v0.10.0")! > ReleaseVersion("0.9.9")!)
        #expect(ReleaseVersion("v1.0.0") == ReleaseVersion("1.0.0"))
        #expect(ReleaseVersion("1.0.0-beta") == nil)
        #expect(ReleaseVersion("1.0") == nil)
        #expect(ReleaseVersion("1/2/3") == nil)
        #expect(ReleaseVersion("999999999999999999999999.1.0") == nil)
    }

    @Test func availableReleasePersistsAndAutomaticChecksAreThrottled() async throws {
        let data = try fixture()
        let prefs = preferences()
        let store = UpdateStore(installedVersion: "0.2.3", preferences: prefs, fetch: { data })
        await store.checkIfNeeded()
        #expect(store.updateAvailable)
        #expect(store.release?.safeDownload != nil)
        #expect(store.release?.body?.contains("Verbesserungen") == true)
        let cached = UpdateStore(installedVersion: "0.2.3", preferences: prefs, fetch: { throw URLError(.notConnectedToInternet) })
        #expect(cached.updateAvailable)
        await cached.checkIfNeeded()
        #expect(!cached.isError) // No request within 24 hours, including after restart.
        prefs.set(Date().addingTimeInterval(-25 * 3600), forKey: "bg.lastUpdateAttempt")
        await cached.checkIfNeeded()
        #expect(cached.isError)
        #expect(cached.updateAvailable) // Known update remains visible while offline.
    }

    @Test func disabledAutomaticCheckDoesNotFetchButManualCheckDoes() async throws {
        let data = try fixture()
        let prefs = preferences()
        prefs.set(false, forKey: "bg.autoUpdateChecks")
        let store = UpdateStore(installedVersion: "0.2.3", preferences: prefs, fetch: { data })
        await store.checkIfNeeded()
        #expect(store.release == nil)
        #expect(prefs.object(forKey: "bg.lastUpdateAttempt") == nil)
        await store.check()
        #expect(store.updateAvailable)
        let current = UpdateStore(installedVersion: "0.3.0", preferences: preferences(), fetch: { data })
        await current.check()
        #expect(!current.updateAvailable)
    }

    @Test func unsafeDownloadAndDigestAreRejected() throws {
        let unsafe = try JSONDecoder().decode(GitHubRelease.self,
            from: fixture(url: "https://example.com/B-Guard.dmg"))
        #expect(unsafe.safeDownload == nil)
        let invalidDigest = try JSONDecoder().decode(GitHubRelease.self, from: fixture(digest: "sha256:wrong"))
        #expect(invalidDigest.safeDownload == nil)
        let good = try JSONDecoder().decode(GitHubRelease.self, from: fixture())
        #expect(throws: (any Error).self) { try UpdateStore.verify(Data("abc".utf8), asset: good.dmg!) }
        let digest = "sha256:" + SHA256.hash(data: Data("abc".utf8)).map { String(format: "%02x", $0) }.joined()
        let verified = try JSONDecoder().decode(GitHubRelease.self, from: fixture(digest: digest))
        try UpdateStore.verify(Data("abc".utf8), asset: verified.dmg!)
        #expect(throws: (any Error).self) { try UpdateStore.verify(Data("abcd".utf8), asset: verified.dmg!) }
    }

    @Test func malformedMetadataNeverBecomesAvailableUpdate() async {
        let store = UpdateStore(installedVersion: "0.2.3", preferences: preferences(), fetch: { Data("invalid".utf8) })
        await store.check()
        #expect(store.isError)
        #expect(!store.updateAvailable)
        #expect(!store.isChecking)
    }
}
