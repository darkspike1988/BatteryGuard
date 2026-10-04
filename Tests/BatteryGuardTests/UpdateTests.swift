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

    @Test func cancellationDiscardsCompletedTemporaryFileWithoutOpeningIt() async throws {
        let data = try fixture()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("abc".utf8).write(to: temporary)
        let gate = DownloadGate()
        let store = UpdateStore(installedVersion: "0.2.3", preferences: preferences(), fetch: { data },
            downloadFile: { url, _, delegate in
                delegate.report(2)
                await gate.wait()
                return (temporary, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        await store.check()
        let task = Task { await store.downloadAndOpen() }
        while !(await gate.started) { await Task.yield() }
        #expect(store.isDownloading)
        store.cancelDownload()
        await gate.release()
        await task.value
        #expect(!store.isDownloading)
        #expect(!store.isError)
        #expect(store.message == "Download abgebrochen.")
        #expect(store.downloadedURL == nil)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test func checksumFailureDiscardsTemporaryDownload() async throws {
        let data = try fixture()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("abc".utf8).write(to: temporary)
        let store = UpdateStore(installedVersion: "0.2.3", preferences: preferences(), fetch: { data },
            downloadFile: { url, _, _ in
                (temporary, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        await store.check()
        await store.downloadAndOpen()
        #expect(store.isError)
        #expect(store.downloadedURL == nil)
        #expect(!store.isDownloading)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test func downloadProgressSizeChecksAndRealDelegateCancel() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://example.com/B-Guard.dmg")!

        // 1. Grenze exakt erlaubt: totalBytesWritten == assetSize und totalBytesExpectedToWrite == assetSize
        let allowedTask = session.downloadTask(with: url)
        let allowedBytes = DownloadByteCounter()
        let allowedProgress = UpdateDownloadProgress(assetSize: 100) { allowedBytes.set($0) }
        allowedProgress.urlSession(session, downloadTask: allowedTask, didWriteData: 100, totalBytesWritten: 100, totalBytesExpectedToWrite: 100)
        #expect(!allowedProgress.hasSizeExceeded)
        #expect(allowedBytes.value == 100)
        #expect(allowedTask.state == .suspended)

        // 2. Unbekannte expected-Größe erlaubt: totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown (-1)
        let unknownExpectedTask = session.downloadTask(with: url)
        let unknownBytes = DownloadByteCounter()
        let unknownProgress = UpdateDownloadProgress(assetSize: 100) { unknownBytes.set($0) }
        unknownProgress.urlSession(session, downloadTask: unknownExpectedTask, didWriteData: 50, totalBytesWritten: 50, totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown)
        #expect(!unknownProgress.hasSizeExceeded)
        #expect(unknownBytes.value == 50)
        #expect(unknownExpectedTask.state == .suspended)

        // 3. Größenbedingung 1: totalBytesWritten größer als asset.size -> echter Delegate-cancel
        let writtenExceededTask = session.downloadTask(with: url)
        let writtenBytes = DownloadByteCounter()
        let writtenProgress = UpdateDownloadProgress(assetSize: 100) { writtenBytes.set($0) }
        writtenProgress.urlSession(session, downloadTask: writtenExceededTask, didWriteData: 101, totalBytesWritten: 101, totalBytesExpectedToWrite: 100)
        #expect(writtenProgress.hasSizeExceeded)
        #expect(writtenBytes.value == 0)
        #expect(writtenExceededTask.state == .canceling)

        // 4. Größenbedingung 2: bekannte totalBytesExpectedToWrite oberhalb asset.size -> echter Delegate-cancel
        let expectedExceededTask = session.downloadTask(with: url)
        let expectedBytes = DownloadByteCounter()
        let expectedProgress = UpdateDownloadProgress(assetSize: 100) { expectedBytes.set($0) }
        expectedProgress.urlSession(session, downloadTask: expectedExceededTask, didWriteData: 10, totalBytesWritten: 10, totalBytesExpectedToWrite: 101)
        #expect(expectedProgress.hasSizeExceeded)
        #expect(expectedBytes.value == 0)
        #expect(expectedExceededTask.state == .canceling)
    }

    @Test func storeTreatsSizeExceededAsLocalizedErrorWhenCancelled() async throws {
        let data = try fixture() // asset.size is 3
        let store = UpdateStore(installedVersion: "0.2.3", preferences: preferences(), fetch: { data },
            downloadFile: { url, session, delegate in
                let task = session.downloadTask(with: url)
                delegate.urlSession(session, downloadTask: task, didWriteData: 4, totalBytesWritten: 4, totalBytesExpectedToWrite: 3)
                throw URLError(.cancelled)
            })
        await store.check()
        await store.downloadAndOpen()
        #expect(store.isError)
        #expect(!store.isDownloading)
        #expect(store.downloadedURL == nil)
        #expect(store.message != "Download abgebrochen.")
        #expect(store.message?.contains(UpdateError.downloadSizeExceeded.localizedDescription) == true)
    }

    @Test func storeRemovesTemporaryFileWhenDownloaderReturnsFileDespiteSizeExceeded() async throws {
        let data = try fixture() // asset.size is 3
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("abcd".utf8).write(to: temporary)

        let store = UpdateStore(installedVersion: "0.2.3", preferences: preferences(), fetch: { data },
            downloadFile: { url, session, delegate in
                let task = session.downloadTask(with: url)
                delegate.urlSession(session, downloadTask: task, didWriteData: 2, totalBytesWritten: 2, totalBytesExpectedToWrite: 5)
                return (temporary, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        await store.check()
        await store.downloadAndOpen()
        #expect(store.isError)
        #expect(!store.isDownloading)
        #expect(store.downloadedURL == nil)
        #expect(store.message != "Download abgebrochen.")
        #expect(store.message?.contains(UpdateError.downloadSizeExceeded.localizedDescription) == true)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test func userCancellationTakesPrecedenceOverSizeExceeded() async throws {
        let data = try fixture()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("abcd".utf8).write(to: temporary)
        let gate = DownloadGate()

        let store = UpdateStore(installedVersion: "0.2.3", preferences: preferences(), fetch: { data },
            downloadFile: { url, session, delegate in
                let task = session.downloadTask(with: url)
                delegate.urlSession(session, downloadTask: task, didWriteData: 10, totalBytesWritten: 10, totalBytesExpectedToWrite: 3)
                await gate.wait()
                return (temporary, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        await store.check()
        let task = Task { await store.downloadAndOpen() }
        while !(await gate.started) { await Task.yield() }
        #expect(store.isDownloading)
        store.cancelDownload()
        await gate.release()
        await task.value
        #expect(!store.isDownloading)
        #expect(!store.isError)
        #expect(store.message == "Download abgebrochen.")
        #expect(store.downloadedURL == nil)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }
}

private actor DownloadGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private final class DownloadByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int64 = 0
    var value: Int64 { lock.withLock { count } }
    func set(_ value: Int64) { lock.withLock { count = value } }
}
