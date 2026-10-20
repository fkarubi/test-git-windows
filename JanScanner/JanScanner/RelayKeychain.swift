import Foundation
import Security

/// リレーの合言葉。UserDefaults やログには出さない。
enum RelayKeychain {
    static let service = "com.example.JanScanner"
    /// 本番のアカウント。テストは別アカウントを渡す。
    static let account = "relay-token"

    static func token(account: String = RelayKeychain.account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = normalize(string)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func save(_ raw: String, account: String = RelayKeychain.account) throws {
        let token = normalize(raw)
        guard !token.isEmpty else { throw RelayKeychainError.empty }
        guard isAcceptable(token) else { throw RelayKeychainError.invalid }
        guard token.count >= 16 else { throw RelayKeychainError.tooShort }
        guard token.count <= 512 else { throw RelayKeychainError.invalid }
        let data = Data(token.utf8)
        let base = keyQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let update = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        if update != errSecItemNotFound {
            SecItemDelete(base as CFDictionary)
        }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw RelayKeychainError.failed }
    }

    static func delete(account: String = RelayKeychain.account) {
        SecItemDelete(keyQuery(account: account) as CFDictionary)
    }

    private static func keyQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 前後の空白を除き、先頭の "Bearer " は外す。値そのものはログに出さない。
    static func normalize(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    static func isAcceptable(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

enum RelayKeychainError: Error, Equatable {
    case empty
    case invalid
    case tooShort
    case failed

    var message: String {
        switch self {
        case .empty:
            return "合言葉が空です。"
        case .invalid:
            return "合言葉に改行や空白は使えません。"
        case .tooShort:
            return "合言葉が短すぎます。16文字以上にしてください。"
        case .failed:
            return "合言葉をキーチェーンに保存できませんでした。"
        }
    }
}
