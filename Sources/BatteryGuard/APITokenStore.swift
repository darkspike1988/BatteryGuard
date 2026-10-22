import Foundation
import Darwin
import Security

struct APITokenStore: Sendable {
    let url: URL
    init(url: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? base.appendingPathComponent("BatteryGuard/api-token")
    }

    private func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid() else { throw POSIXError(.EPERM) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private enum Existing {
        case missing
        case valid(String)
        /// Eigene, reguläre Datei mit falschem Inhalt oder zu offenen Rechten (z. B. nach
        /// einem Absturz beim Schreiben oder einer Wiederherstellung). Sie wird ersetzt.
        case damaged
    }

    /// Fremde, verlinkte oder nicht reguläre Pfade werden nie angefasst.
    private func inspect() throws -> Existing {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            guard errno == ENOENT else { throw POSIXError(.EPERM) }
            return .missing
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else {
            throw POSIXError(.EPERM)
        }
        guard info.st_mode & 0o077 == 0, info.st_size == 64,
              let data = try handle.read(upToCount: 65),
              let token = String(data: data, encoding: .utf8), Self.isValid(token) else { return .damaged }
        return .valid(token)
    }

    func loadOrCreate() throws -> String {
        try prepareDirectory()
        switch try inspect() {
        case .valid(let token): return token
        case .missing: return try store(Self.generate(), replacing: false)
        case .damaged: return try store(Self.generate(), replacing: true)
        }
    }

    func rotate() throws -> String {
        try prepareDirectory()
        _ = try inspect() // Refuse unsafe existing paths before replacing them.
        return try store(Self.generate(), replacing: true)
    }

    /// Vollständig geschriebene 0600-Datei, dann atomar an ihren Platz: `link` für eine
    /// neue Datei (scheitert, wenn parallel eine entstand), `rename` zum Ersetzen.
    private func store(_ token: String, replacing: Bool) throws -> String {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { _ = unlink(temporary.path) }
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data(token.utf8))
            guard fchmod(fd, 0o600) == 0 else { throw POSIXError(.EIO) }
            try handle.synchronize()
        }
        if replacing {
            guard rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
        } else if link(temporary.path, url.path) != 0 {
            if errno == EEXIST { return try loadOrCreate() }
            throw POSIXError(.EIO)
        }
        return token
    }

    static func isValid(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw POSIXError(.EIO)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func matchesAuthorization(_ header: String?, token: String) -> Bool {
        guard let header else { return false }
        let expected = Array(("Bearer " + token).utf8)
        let actual = Array(header.utf8)
        guard actual.count == expected.count else { return false }
        return zip(actual, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
