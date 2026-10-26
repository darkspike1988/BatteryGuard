import Foundation
import Security
import BatteryGuardShared

/// Schlüssel für den verschlüsselten Verlauf im Anmelde-Schlüsselbund des Benutzers.
enum HistoryKeyStore {
    static let preferenceKey = "bg.encryptHistory"
    private static let service = "com.batteryguard.history"
    private static let account = "history-key"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: preferenceKey) }

    /// Vorhandenen Schlüssel lesen; nil, wenn keiner existiert oder der Schlüsselbund ablehnt.
    static func cipher() -> BGHistoryCipher? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? BGHistoryCipher(keyData: data)
    }

    /// Schlüssel anlegen, falls keiner existiert.
    static func cipherCreatingKey() -> BGHistoryCipher? {
        if let existing = cipher() { return existing }
        let keyData = BGHistoryCipher.newKeyData()
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                         kSecAttrAccount as String: account, kSecValueData as String: keyData,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                         kSecAttrLabel as String: "B-Guard Verlaufsschlüssel"]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { return nil }
        return try? BGHistoryCipher(keyData: keyData)
    }
}
