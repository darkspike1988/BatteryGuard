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

    func loadOrCreate() throws -> String {
        try prepareDirectory()
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            guard errno == ENOENT else { throw POSIXError(.EPERM) }
            let token = try Self.generate()
            let output = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard output >= 0 else {
                if errno == EEXIST { return try loadOrCreate() }
                throw POSIXError(.EIO)
            }
            let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data(token.utf8))
            try handle.synchronize()
            return token
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0, info.st_size == 64 else {
            throw POSIXError(.EPERM)
        }
        let data = try handle.read(upToCount: 65) ?? Data()
        guard let token = String(data: data, encoding: .utf8), Self.isValid(token) else {
            throw POSIXError(.EINVAL)
        }
        return token
    }

    func rotate() throws -> String {
        _ = try loadOrCreate() // Refuse unsafe existing paths before replacing them.
        let token = try Self.generate()
        try Data(token.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
