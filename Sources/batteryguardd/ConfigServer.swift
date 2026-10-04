import Foundation
import Darwin
import SystemConfiguration
import BatteryGuardShared

/// Root owns the listener and configuration. Only root and the current console
/// user can submit typed changes, never paths or commands. Work stays off the
/// daemon's power-event/run-loop thread.
final class ConfigServer: @unchecked Sendable {
    private let stateLock = NSLock()
    private var running = false
    private var listener: Int32 = -1
    private let queue = DispatchQueue(label: "com.batteryguard.config-ipc", qos: .utility)

    func start() throws {
        guard geteuid() == 0 else { throw BGConfigIPCError.unauthorized }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running, listener == -1 else { throw POSIXError(.EALREADY) }
        var directory = stat()
        guard lstat(BGPaths.directory, &directory) == 0,
              (directory.st_mode & S_IFMT) == S_IFDIR,
              directory.st_uid == 0, directory.st_mode & 0o022 == 0 else {
            throw BGConfigIPCError.unauthorized
        }
        var existing = stat()
        if lstat(BGConfigWire.socketPath, &existing) == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFSOCK, existing.st_uid == 0 else {
                throw BGConfigIPCError.unauthorized
            }
            // Do not steal a listener from another running daemon instance.
            let probe = socket(AF_UNIX, SOCK_STREAM, 0)
            guard probe >= 0 else { throw BGConfigWire.posixError() }
            defer { _ = close(probe) }
            try BGConfigWire.configure(probe)
            var address = try BGConfigWire.address(BGConfigWire.socketPath)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result == 0 || errno == EINPROGRESS { throw POSIXError(.EADDRINUSE) }
            guard errno == ECONNREFUSED || errno == ENOENT else { throw BGConfigWire.posixError() }
            guard unlink(BGConfigWire.socketPath) == 0 || errno == ENOENT else { throw BGConfigWire.posixError() }
        } else if errno != ENOENT { throw BGConfigWire.posixError() }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BGConfigWire.posixError() }
        var installed = false
        var bound = false
        defer {
            if !installed {
                _ = close(descriptor)
                if bound { _ = unlink(BGConfigWire.socketPath) }
            }
        }
        try BGConfigWire.configure(descriptor)
        var address = try BGConfigWire.address(BGConfigWire.socketPath)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw BGConfigWire.posixError() }
        bound = true
        guard chmod(BGConfigWire.socketPath, 0o666) == 0,
              listen(descriptor, 16) == 0 else { throw BGConfigWire.posixError() }
        listener = descriptor
        running = true
        installed = true
        queue.async { [self] in serve(descriptor) }
    }

    /// Nonblocking shutdown: the accept loop observes this within 250 ms; any
    /// current authorized request already has an absolute one-second deadline.
    func stop() {
        stateLock.lock()
        running = false
        stateLock.unlock()
    }

    private func isRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private func serve(_ descriptor: Int32) {
        defer {
            _ = close(descriptor)
            _ = unlink(BGConfigWire.socketPath)
            stateLock.lock()
            listener = -1
            running = false
            stateLock.unlock()
        }
        while isRunning() {
            var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&item, 1, 250)
            if ready < 0 {
                if errno == EINTR { continue }
                return
            }
            guard ready > 0 else { continue }
            guard item.revents & Int16(POLLIN) != 0 else { return }
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            handle(client)
            _ = close(client)
        }
    }

    private func handle(_ descriptor: Int32) {
        do {
            try BGConfigWire.configure(descriptor)
            let uid = try BGConfigWire.peerUID(descriptor)
            // Deny before reading. An unprivileged non-console process cannot
            // monopolize the listener by holding a connection open.
            guard BGConfigPeerPolicy.allows(peerUID: uid, consoleUID: Self.consoleUID()) else { return }
            let deadline = ProcessInfo.processInfo.systemUptime + BGConfigWire.timeout
            let request = try BGConfigWire.receive(BGConfigRequest.self, from: descriptor, until: deadline)
            let response: BGConfigResponse
            do {
                // Recheck console identity after receipt, including fast user switching.
                let saved = try Self.apply(request, peerUID: uid, consoleUID: Self.consoleUID())
                response = BGConfigResponse(config: saved)
            } catch {
                response = BGConfigResponse(error: "Die Einstellungen konnten nicht gespeichert werden. " + error.localizedDescription)
            }
            try BGConfigWire.send(response, to: descriptor, until: deadline)
        } catch { /* Disconnect malformed, oversized or stalled requests. */ }
    }

    static func consoleUID() -> uid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid),
              name as String != "loginwindow", uid != 0 else { return nil }
        return uid
    }

    /// Testable authorization and transactional merge; the endpoint never
    /// accepts configURL from a request. Tests provide only temporary files.
    static func apply(_ request: BGConfigRequest, peerUID: uid_t, consoleUID: uid_t?,
                      configURL: URL = URL(fileURLWithPath: BGPaths.config)) throws -> BGConfig {
        guard BGConfigPeerPolicy.allows(peerUID: peerUID, consoleUID: consoleUID) else {
            throw BGConfigIPCError.unauthorized
        }
        guard request.protocolVersion == 1 else { throw BGConfigIPCError.invalidMessage }
        if request.queryOnly == true { return try BGConfigFile.read(at: configURL) }
        return try BGConfigFile.update(at: configURL) { latest in
            latest = request.desired.mergingEdits(since: request.baseline, into: latest)
        }
    }
}
