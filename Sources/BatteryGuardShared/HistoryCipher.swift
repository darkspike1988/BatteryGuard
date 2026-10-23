import Foundation
import CryptoKit

/// Optionale Verschlüsselung des lokalen Verlaufs (AES-GCM, 256 Bit). Verschlüsselte Dateien beginnen mit „BGENC1“.
public struct BGHistoryCipher: Sendable {
    public static let magic = Data("BGENC1".utf8)
    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == 32 else { throw BGChargingActionError.invalidRequest("Ungültiger Verlaufsschlüssel.") }
        key = SymmetricKey(data: keyData)
    }

    public static func newKeyData() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func isEncrypted(_ data: Data) -> Bool { data.starts(with: magic) }

    public func seal(_ plain: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw BGChargingActionError.invalidRequest("Verlauf konnte nicht verschlüsselt werden.")
        }
        return Self.magic + combined
    }

    public func open(_ data: Data) throws -> Data {
        guard Self.isEncrypted(data) else { return data }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count)), using: key)
    }
}
