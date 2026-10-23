import Foundation
import IOKit
import BatteryGuardShared

/// Struct-Layout für AppleSMC UserClient gemäß smcFanControl / Battery-Toolkit
@frozen
public struct SMCVersion: Sendable {
    public var major: UInt8 = 0
    public var minor: UInt8 = 0
    public var build: UInt8 = 0
    public var reserved: UInt8 = 0
    public var release: UInt16 = 0
    private var _pad: UInt16 = 0

    public init() {}
}

@frozen
public struct SMCPLimitData: Sendable {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0

    public init() {}
}

@frozen
public struct SMCKeyInfo: Sendable {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0
    private var _pad0: UInt8 = 0
    private var _pad1: UInt8 = 0
    private var _pad2: UInt8 = 0

    public init() {}
}

@frozen
public struct SMCKeyData: Sendable {
    public var key: UInt32 = 0
    public var vers: SMCVersion = SMCVersion()
    public var pLimitData: SMCPLimitData = SMCPLimitData()
    public var keyInfo: SMCKeyInfo = SMCKeyInfo()
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    private var _pad: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    public init() {}
}

public final class SMCClient: @unchecked Sendable {
    public static let shared = SMCClient()

    private let selector: UInt32 = 2 // kSMCHandleYPCEvent
    private let cmdReadBytes: UInt8 = 5
    private let cmdWriteBytes: UInt8 = 6
    private let cmdReadKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    private let lock = NSRecursiveLock()
    /// Die Schlüsselmenge ändert sich zur Laufzeit nicht. Nur eindeutige Antworten des SMC
    /// (vorhanden oder „nicht gefunden“) werden zwischengespeichert, nie IOKit-Fehler.
    private var keyExistence: [String: Bool] = [:]
    private var capabilityCache: BGChargeCapability?
    /// Im Probelauf wird nicht geschrieben; vorhandene Schlüssel gelten dann als `.unknown`.
    public var allowsWriteProbe = true

    public init() {}

    deinit {
        close()
    }

    @discardableResult
    public func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            return true
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return false
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else {
            return false
        }

        self.connection = conn
        return true
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        keyExistence.removeAll()
        capabilityCache = nil
    }

    public func keyExists(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let cached = keyExistence[key] { return cached }
        guard ensureConnected() else { return false }

        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = cmdReadKeyInfo
        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.size
        let kr = IOConnectCallStructMethod(connection, selector, &input, MemoryLayout<SMCKeyData>.size, &output, &outSize)
        guard kr == KERN_SUCCESS else { return false }
        let exists = output.result == 0
        keyExistence[key] = exists
        return exists
    }

    public func readKeyInfo(_ key: String) -> (type: String, size: UInt32)? {
        lock.lock()
        defer { lock.unlock() }

        guard ensureConnected() else { return nil }

        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = cmdReadKeyInfo

        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.size

        let kr = IOConnectCallStructMethod(connection, selector, &input, MemoryLayout<SMCKeyData>.size, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else {
            return nil
        }

        let typeStr = fourCharString(output.keyInfo.dataType)
        return (typeStr, output.keyInfo.dataSize)
    }

    public func readKey(_ key: String) -> (type: String, size: UInt32, bytes: [UInt8])? {
        lock.lock()
        defer { lock.unlock() }

        guard ensureConnected() else { return nil }

        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = cmdReadKeyInfo

        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.size

        let infoKr = IOConnectCallStructMethod(connection, selector, &input, MemoryLayout<SMCKeyData>.size, &output, &outSize)
        guard infoKr == KERN_SUCCESS && output.result == 0 else {
            return nil
        }

        let dataSize = output.keyInfo.dataSize
        let typeStr = fourCharString(output.keyInfo.dataType)

        guard dataSize > 0 && dataSize <= 32 else {
            return (typeStr, dataSize, [])
        }

        var readInput = SMCKeyData()
        readInput.key = fourCharCode(key)
        readInput.keyInfo.dataSize = dataSize
        readInput.data8 = cmdReadBytes

        var readOutput = SMCKeyData()
        var readOutSize = MemoryLayout<SMCKeyData>.size

        let readKr = IOConnectCallStructMethod(connection, selector, &readInput, MemoryLayout<SMCKeyData>.size, &readOutput, &readOutSize)
        guard readKr == KERN_SUCCESS && readOutput.result == 0 else {
            return (typeStr, dataSize, [])
        }

        var byteArray: [UInt8] = []
        withUnsafeBytes(of: readOutput.bytes) { rawPtr in
            byteArray = Array(rawPtr.prefix(Int(dataSize)))
        }

        return (typeStr, dataSize, byteArray)
    }

    public enum WriteResult: Equatable, Sendable {
        case ok, notPrivileged, failed
    }

    /// kIOReturnNotPrivileged: Ab macOS 27 verweigert die Firmware gesperrte Schlüssel auch root.
    static let notPrivileged = kern_return_t(bitPattern: 0xE000_02C1)

    public func writeKey(_ key: String, bytes: [UInt8]) -> Bool {
        writeKeyResult(key, bytes: bytes) == .ok
    }

    public func writeKeyResult(_ key: String, bytes: [UInt8]) -> WriteResult {
        lock.lock()
        defer { lock.unlock() }

        guard ensureConnected() else { return .failed }
        guard bytes.count <= 32 else { return .failed }

        var infoInput = SMCKeyData()
        infoInput.key = fourCharCode(key)
        infoInput.data8 = cmdReadKeyInfo

        var infoOutput = SMCKeyData()
        var infoOutSize = MemoryLayout<SMCKeyData>.size

        let infoKr = IOConnectCallStructMethod(connection, selector, &infoInput, MemoryLayout<SMCKeyData>.size, &infoOutput, &infoOutSize)
        guard infoKr == KERN_SUCCESS && infoOutput.result == 0 else {
            return .failed
        }

        let expectedSize = infoOutput.keyInfo.dataSize
        guard bytes.count == Int(expectedSize) else {
            return .failed
        }

        var writeInput = SMCKeyData()
        writeInput.key = fourCharCode(key)
        writeInput.data8 = cmdWriteBytes
        writeInput.keyInfo.dataSize = expectedSize

        withUnsafeMutableBytes(of: &writeInput.bytes) { rawPtr in
            for i in 0..<bytes.count {
                rawPtr[i] = bytes[i]
            }
        }

        var writeOutput = SMCKeyData()
        var writeOutSize = MemoryLayout<SMCKeyData>.size

        let writeKr = IOConnectCallStructMethod(connection, selector, &writeInput, MemoryLayout<SMCKeyData>.size, &writeOutput, &writeOutSize)
        if writeKr == Self.notPrivileged { return .notPrivileged }
        return writeKr == KERN_SUCCESS && writeOutput.result == 0 ? .ok : .failed
    }

    /// Liest Akkutemperatur über SMC (z. B. TB0T, TB1T, TB2T)
    public func readBatteryTemperature() -> Double? {
        for key in ["TB0T", "TB1T", "TB2T"] {
            guard let keyData = readKey(key), !keyData.bytes.isEmpty else {
                continue
            }
            if keyData.size == 4 {
                // Float32 (flt )
                let floatVal = keyData.bytes.withUnsafeBytes { rawPtr in
                    rawPtr.loadUnaligned(as: Float32.self)
                }
                if floatVal > 0.0 && floatVal < 120.0 {
                    let formatted = String(format: "%.1f", floatVal)
                    return Double(formatted) ?? Double(round(floatVal * 10.0) / 10.0)
                }
            } else if keyData.size == 2 {
                // sp78 fixed point (1 Sign + 7 Bit Integer + 8 Bit Fraction)
                let rawInt = (Int16(keyData.bytes[0]) << 8) | Int16(keyData.bytes[1])
                let celsius = Double(rawInt) / 256.0
                if celsius > 0.0 && celsius < 120.0 {
                    return round(celsius * 10.0) / 10.0
                }
            }
        }
        return nil
    }

    /// Auf diesem Mac als dreibytes CHLT bestätigt. Unbekannte Layouts ignorieren.
    /// Keine privaten Apple-APIs und kein Schreiben des nativen Limits.
    public func readNativeChargeLimit() -> Int? {
        guard let data = readKey("CHLT"), data.size == 3, data.bytes.count == 3 else { return nil }
        let limit = Int(data.bytes[0])
        return (20...100).contains(limit) ? limit : nil
    }

    // MARK: - High-level SMC-Steuerung

    public func detectSupportedKeys() -> [String] {
        let keysToCheck = ["CHTE", "CH0B", "CH0C", "CHIE", "CH0J", "CH0I"]
        return keysToCheck.filter { keyExists($0) }
    }

    /// Prüft einmal pro Verbindung, welche Steuerschlüssel tatsächlich beschreibbar sind.
    /// Der Schreibtest schreibt den gelesenen Wert unverändert zurück und nur, wenn er einem
    /// bekannten Registerlayout entspricht.
    public func chargeCapability() -> BGChargeCapability {
        lock.lock()
        defer { lock.unlock() }
        if let capabilityCache { return capabilityCache }
        var keys: [String: BGSMCKeyState] = [:]
        for key in BGChargeCapability.probedKeys {
            keys[key] = probe(key)
        }
        let capability = BGChargeCapability(keys: keys)
        // Ohne Verbindung nichts zwischenspeichern, sonst bliebe ein IOKit-Fehler bestehen.
        if connection != 0 { capabilityCache = capability }
        return capability
    }

    private func probe(_ key: String) -> BGSMCKeyState {
        guard keyExists(key) else { return .absent }
        guard let value = readKey(key) else { return .unknown }
        if value.size == 0 { return .placeholder }
        guard allowsWriteProbe,
              Self.verifyControlRegister(key: key, size: value.size, bytes: value.bytes,
                                         expectedEnabled: true) != .unavailable else { return .unknown }
        switch writeKeyResult(key, bytes: value.bytes) {
        case .ok: return .writable
        case .notPrivileged: return .blocked
        case .failed: return .unknown
        }
    }

    private func usableKey(_ candidates: [String]) -> String? {
        let capability = chargeCapability()
        return candidates.first { capability.keys[$0] == .writable || capability.keys[$0] == .unknown }
    }

    public var hasChargeControl: Bool {
        chargeCapability().chargeInhibitAvailable
    }

    public var hasDischargeControl: Bool {
        chargeCapability().adapterSwitchAvailable
    }

    public enum ControlReadback: Equatable, Sendable {
        case matches, drift, unavailable
    }

    /// Only decode the exact register layouts already used by our setters.
    public static func verifyControlRegister(key: String, size: UInt32, bytes: [UInt8],
                                             expectedEnabled: Bool) -> ControlReadback {
        let enabled: [UInt8]
        let disabled: [UInt8]
        switch key {
        case "CHTE": enabled = [0, 0, 0, 0]; disabled = [1, 0, 0, 0]
        case "CH0B", "CH0C": enabled = [0]; disabled = [2]
        case "CHIE": enabled = [0]; disabled = [8]
        case "CH0J", "CH0I": enabled = [0]; disabled = [1]
        default: return .unavailable
        }
        guard size == enabled.count, bytes.count == enabled.count,
              bytes == enabled || bytes == disabled else { return .unavailable }
        return bytes == (expectedEnabled ? enabled : disabled) ? .matches : .drift
    }

    private func verifyRegister(_ key: String, expectedEnabled: Bool) -> ControlReadback {
        guard let value = readKey(key) else { return .unavailable }
        return Self.verifyControlRegister(key: key, size: value.size, bytes: value.bytes,
                                          expectedEnabled: expectedEnabled)
    }

    public func verifyChargingEnabled(_ expected: Bool) -> ControlReadback {
        guard let key = usableKey(["CHTE", "CH0B"]) else { return .unavailable }
        if key == "CHTE" { return verifyRegister("CHTE", expectedEnabled: expected) }
        let primary = verifyRegister("CH0B", expectedEnabled: expected)
        guard usableKey(["CH0C"]) != nil else { return primary }
        let secondary = verifyRegister("CH0C", expectedEnabled: expected)
        // Both charge registers must be readable and agree with the applied target.
        if primary == .unavailable || secondary == .unavailable { return .unavailable }
        return primary == .matches && secondary == .matches ? .matches : .drift
    }

    public func verifyAdapterConnected(_ expected: Bool) -> ControlReadback {
        guard let key = usableKey(BGChargeCapability.adapterKeys) else { return .unavailable }
        return verifyRegister(key, expectedEnabled: expected)
    }

    /// Laden ein- oder ausschalten
    /// CHTE (4 Byte): aus = 01 00 00 00, an = 00 00 00 00
    /// CH0B / CH0C (1 Byte): aus = 02, an = 00
    public func setChargingEnabled(_ enabled: Bool) -> Bool {
        let key = usableKey(["CHTE", "CH0B"])
        if key == "CHTE" {
            let bytes: [UInt8] = enabled ? [0x00, 0x00, 0x00, 0x00] : [0x01, 0x00, 0x00, 0x00]
            _ = writeKey("CHTE", bytes: bytes)
            return readKey("CHTE")?.bytes == bytes
        } else if key == "CH0B" {
            let byte: [UInt8] = enabled ? [0x00] : [0x02]
            var success = writeKey("CH0B", bytes: byte)
            if success { success = readKey("CH0B")?.bytes == byte }
            if usableKey(["CH0C"]) != nil {
                let s2 = writeKey("CH0C", bytes: byte)
                success = success && s2 && (readKey("CH0C")?.bytes == byte)
            }
            return success
        }
        return false
    }

    /// Adapter trennen (aktiv entladen) oder verbinden
    /// CHIE = 08 (an / getrennt) / 00 (aus / verbunden) bevorzugt,
    /// sonst CH0J = 01 / 00,
    /// sonst CH0I = 01 / 00.
    public func setAdapterConnected(_ connected: Bool) -> Bool {
        guard let key = usableKey(BGChargeCapability.adapterKeys) else { return false }
        let bytes: [UInt8] = connected ? [0x00] : [key == "CHIE" ? 0x08 : 0x01]
        _ = writeKey(key, bytes: bytes)
        return readKey(key)?.bytes == bytes
    }

    public enum MagSafeColor: UInt8 {
        case auto = 0x00
        case off = 0x01
        case green = 0x03
        case orange = 0x04
    }

    /// Setzt die MagSafe-LED-Farbe (ACLC).
    @discardableResult
    public func setMagSafeLED(_ color: MagSafeColor) -> Bool {
        if keyExists("ACLC") {
            let bytes: [UInt8] = [color.rawValue]
            _ = writeKey("ACLC", bytes: bytes)
            return readKey("ACLC")?.bytes == bytes
        }
        return false
    }

    /// Normalzustand wiederherstellen (Laden an, Adapter an, LED Auto)
    @discardableResult
    public func restoreNormal() -> Bool {
        let a = !hasDischargeControl || setAdapterConnected(true)
        let c = !hasChargeControl || setChargingEnabled(true)
        let l = !keyExists("ACLC") || setMagSafeLED(.auto)
        return a && c && l
    }

    // MARK: - Diagnose (nur lesend)

    /// Listet alle SMC-Keys (optional nach Präfix gefiltert) mit Typ, Größe und aktuellem Wert.
    public func listAllKeys(prefixes: [String] = []) -> [(key: String, type: String, size: UInt32, bytes: [UInt8])] {
        lock.lock()
        defer { lock.unlock() }
        guard ensureConnected() else { return [] }

        var count: UInt32 = 0
        if let k = readKey("#KEY"), k.bytes.count == 4 {
            count = k.bytes.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        }
        var result: [(key: String, type: String, size: UInt32, bytes: [UInt8])] = []
        for index in 0..<count {
            var input = SMCKeyData()
            input.data8 = 8 // kSMCGetKeyFromIndex
            input.data32 = index
            var output = SMCKeyData()
            var outSize = MemoryLayout<SMCKeyData>.size
            let kr = IOConnectCallStructMethod(connection, selector, &input, MemoryLayout<SMCKeyData>.size, &output, &outSize)
            guard kr == KERN_SUCCESS, output.result == 0 else { continue }
            let name = fourCharString(output.key)
            if !prefixes.isEmpty && !prefixes.contains(where: { name.hasPrefix($0) }) { continue }
            if let v = readKey(name) {
                result.append((name, v.type, v.size, v.bytes))
            } else {
                result.append((name, "?", 0, []))
            }
        }
        return result
    }

    // MARK: - Private Hilfsmethoden


    private func ensureConnected() -> Bool {
        if connection != 0 { return true }
        return open()
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        var res: UInt32 = 0
        for b in str.utf8.prefix(4) {
            res = (res << 8) | UInt32(b)
        }
        return res
    }

    private func fourCharString(_ code: UInt32) -> String {
        let b0 = UInt8((code >> 24) & 0xFF)
        let b1 = UInt8((code >> 16) & 0xFF)
        let b2 = UInt8((code >> 8) & 0xFF)
        let b3 = UInt8(code & 0xFF)
        return [b0, b1, b2, b3].map { b in
            if b >= 32 && b <= 126 {
                return String(UnicodeScalar(b))
            } else {
                return "?"
            }
        }.joined()
    }
}
