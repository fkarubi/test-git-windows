import Foundation
import Security

/// 中継サーバーの合言葉をキーチェーンにだけ保存する。
/// 値を画面に再表示する用途の読み出しはせず、送信時にだけ読む。
enum PassphraseKeychain {
    private static let service = "JanScanner.relay"
    private static let account = "passphrase"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "キーチェーンに保存できませんでした（\(status)）" }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ passphrase: String) throws {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(passphrase.utf8)
        // この端末だけ・ロック解除中だけ読める（バックアップで他の端末へ移らない）
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 保存済みかどうかだけを調べる（値は読み出さない）
    static var isSaved: Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
